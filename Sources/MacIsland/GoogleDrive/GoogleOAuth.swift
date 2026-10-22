import AppKit
import CryptoKit
import Network
import Security

@MainActor
final class GoogleOAuth {
  private var receiver: LoopbackReceiver?
  private let session = URLSession(configuration: .ephemeral)

  func connect(_ configuration: GoogleClientConfiguration) async throws -> GoogleTokens {
    let verifier = try Self.random()
    let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    let state = try Self.random()
    let receiver = LoopbackReceiver()
    self.receiver = receiver
    defer { self.receiver = nil }
    let result = try await receiver.receive(state: state) { redirect in
      var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
      url.queryItems = [
        .init(name: "client_id", value: configuration.clientID),
        .init(name: "redirect_uri", value: redirect),
        .init(name: "response_type", value: "code"),
        .init(name: "scope", value: "https://www.googleapis.com/auth/drive"),
        .init(name: "access_type", value: "offline"),
        .init(name: "prompt", value: "consent select_account"),
        .init(name: "code_challenge", value: challenge),
        .init(name: "code_challenge_method", value: "S256"),
        .init(name: "state", value: state),
      ]
      return url.url!
    }
    return try await token(
      configuration,
      fields: [
        "code": result.code, "code_verifier": verifier,
        "redirect_uri": result.redirect, "grant_type": "authorization_code",
      ], existingRefreshToken: nil)
  }

  func refresh(_ tokens: GoogleTokens, configuration: GoogleClientConfiguration) async throws
    -> GoogleTokens
  {
    try await token(
      configuration, fields: ["refresh_token": tokens.refreshToken, "grant_type": "refresh_token"],
      existingRefreshToken: tokens.refreshToken)
  }

  func cancel() { receiver?.cancel() }

  private func token(
    _ configuration: GoogleClientConfiguration, fields: [String: String],
    existingRefreshToken: String?
  ) async throws -> GoogleTokens {
    var fields = fields
    fields["client_id"] = configuration.clientID
    fields["client_secret"] = configuration.clientSecret
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    let form = fields.map { key, value in
      "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
    }.joined(separator: "&")
    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    request.httpMethod = "POST"
    request.httpBody = Data(form.utf8)
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 30
    let (data, response) = try await session.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw DriveFailure.message(
        "Google sign-in failed. Check the desktop OAuth client and the test-user list, then reconnect."
      )
    }
    struct Reply: Decodable {
      let access_token: String
      let refresh_token: String?
      let expires_in: Double
    }
    let result = try JSONDecoder().decode(Reply.self, from: data)
    guard let refresh = result.refresh_token ?? existingRefreshToken else {
      throw DriveFailure.message(
        "Google did not return offline access. Reconnect and allow access.")
    }
    return GoogleTokens(
      accessToken: result.access_token, refreshToken: refresh,
      expires: Date().addingTimeInterval(result.expires_in))
  }

  nonisolated private static func random() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw DriveFailure.message("Could not start secure Google sign-in.")
    }
    return base64URL(Data(bytes))
  }
  nonisolated private static func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(
      of: "/", with: "_"
    ).replacingOccurrences(of: "=", with: "")
  }
}

@MainActor
private final class LoopbackReceiver {
  private var listener: NWListener?
  private var result: CheckedContinuation<(code: String, redirect: String), Error>?
  private var timeout: Task<Void, Never>?
  private var redirect = ""

  func receive(state: String, authorizationURL: @escaping (String) -> URL) async throws -> (
    code: String, redirect: String
  ) {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    let listener = try NWListener(using: parameters)
    self.listener = listener
    return try await withCheckedThrowingContinuation { continuation in
      result = continuation
      listener.stateUpdateHandler = { [weak self] status in
        MainActor.assumeIsolated {
          guard let self else { return }
          if case .ready = status, let port = listener.port {
            self.redirect = "http://127.0.0.1:\(port.rawValue)/oauth/callback"
            if !NSWorkspace.shared.open(authorizationURL(self.redirect)) {
              self.finish(.failure(DriveFailure.message("Could not open the browser.")))
            }
          } else if case .failed = status {
            self.finish(
              .failure(DriveFailure.message("Could not start the local Google sign-in callback.")))
          }
        }
      }
      listener.newConnectionHandler = { [weak self] connection in
        connection.start(queue: .main)
        MainActor.assumeIsolated { self?.read(connection, state: state, buffer: Data()) }
      }
      listener.start(queue: .main)
      timeout = Task { [weak self] in
        try? await Task.sleep(for: .seconds(180))
        guard !Task.isCancelled else { return }
        self?.finish(
          .failure(DriveFailure.message("Google sign-in timed out. Select Connect to try again.")))
      }
    }
  }

  private func read(_ connection: NWConnection, state: String, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
      [weak self] data, _, complete, error in
      MainActor.assumeIsolated {
        guard let self else {
          connection.cancel()
          return
        }
        var buffer = buffer
        if let data { buffer.append(data) }
        guard buffer.count <= 16384, error == nil else {
          connection.cancel()
          return
        }
        guard let request = String(data: buffer, encoding: .utf8), request.contains("\r\n\r\n")
        else {
          if !complete {
            self.read(connection, state: state, buffer: buffer)
          } else {
            connection.cancel()
          }
          return
        }
        let parts = request.components(separatedBy: "\r\n")[0].split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
          let url = URLComponents(string: "http://127.0.0.1\(parts[1])"),
          url.path == "/oauth/callback",
          url.queryItems?.first(where: { $0.name == "state" })?.value == state
        else {
          connection.cancel()
          return
        }
        let code = url.queryItems?.first(where: { $0.name == "code" })?.value
        let body =
          "<html><body><h2>Return to Mac Island</h2><p>You can close this browser tab.</p></body></html>"
        let response =
          "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(
          content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        if let code {
          self.finish(.success((code, self.redirect)))
        } else {
          self.finish(
            .failure(DriveFailure.message("Google sign-in was cancelled or access was denied.")))
        }
      }
    }
  }

  func cancel() { finish(.failure(CancellationError())) }
  private func finish(_ value: Result<(code: String, redirect: String), Error>) {
    guard let result else { return }
    self.result = nil
    timeout?.cancel()
    listener?.stateUpdateHandler = nil
    listener?.newConnectionHandler = nil
    listener?.cancel()
    listener = nil
    result.resume(with: value)
  }
}
