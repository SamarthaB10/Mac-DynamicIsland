import AppKit
import Network

@MainActor
final class LoopbackReceiver {
  private var listener: NWListener?
  private var result: CheckedContinuation<(code: String, redirect: String), Error>?
  private var timeout: Task<Void, Never>?
  private var redirect = ""

  func receive(state: String, port: NWEndpoint.Port = .any, authorizationURL: @escaping (String) -> URL) async throws -> (
    code: String, redirect: String
  ) {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
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
              self.finish(.failure(OAuthCallbackFailure.message("Could not open the browser.")))
            }
          } else if case .failed = status {
            self.finish(
              .failure(OAuthCallbackFailure.message("Could not start the local sign-in callback.")))
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
          .failure(OAuthCallbackFailure.message("Sign-in timed out. Select Connect to try again.")))
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
            .failure(OAuthCallbackFailure.message("Sign-in was cancelled or access was denied.")))
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

enum OAuthCallbackFailure: LocalizedError {
  case message(String)
  var errorDescription: String? {
    if case .message(let message) = self { return message }
    return nil
  }
}
