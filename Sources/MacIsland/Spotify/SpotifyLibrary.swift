import AppKit
import CryptoKit
import Network
import Security

@MainActor
final class SpotifyLibrary: ObservableObject {
  static let redirectURI = "http://127.0.0.1:43827/oauth/callback"
  @Published private(set) var connected = false
  @Published private(set) var connecting = false
  @Published private(set) var saving = false
  @Published private(set) var saved: Bool?
  @Published var error: String?
  private var authGeneration = 0
  private var revision = 0
  private var currentURI: String?
  private var credentials: Credentials?
  private var receiver: LoopbackReceiver?
  private var refreshTask: Task<Credentials, Error>?
  private let session = URLSession(configuration: .ephemeral)
  private let service = "local.macisland.spotify"

  private struct Credentials: Codable {
    let clientID: String
    let accessToken: String
    let refreshToken: String
    let expires: Date
  }

  init() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: "account", kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecSuccess, let data = item as? Data {
      credentials = try? JSONDecoder().decode(Credentials.self, from: data)
      connected = credentials != nil
    } else if status != errSecItemNotFound {
      error = "Spotify sign-in could not be read from Keychain. Connect again."
    }
  }

  func connect(clientID: String) async -> Bool {
    guard !connecting else { return false }
    authGeneration += 1
    refreshTask?.cancel()
    refreshTask = nil
    connecting = true
    connected = false
    saved = nil
    error = nil
    defer { connecting = false; receiver = nil; connected = credentials != nil }
    do {
      let verifier = try random()
      let state = try random()
      let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
      let receiver = LoopbackReceiver()
      self.receiver = receiver
      let callback = try await receiver.receive(state: state, port: 43827) { redirect in
        var url = URLComponents(string: "https://accounts.spotify.com/authorize")!
        url.queryItems = [
          .init(name: "client_id", value: clientID), .init(name: "response_type", value: "code"),
          .init(name: "redirect_uri", value: redirect),
          .init(name: "scope", value: "user-library-read user-library-modify"),
          .init(name: "state", value: state), .init(name: "code_challenge", value: challenge),
          .init(name: "code_challenge_method", value: "S256"),
        ]
        return url.url!
      }
      let credentials = try await token(clientID: clientID, fields: [
        "grant_type": "authorization_code", "code": callback.code,
        "redirect_uri": callback.redirect, "code_verifier": verifier,
      ])
      try Task.checkCancellation()
      try store(credentials)
      UserDefaults.standard.set(clientID, forKey: "spotifyClientID")
      self.credentials = credentials
      connected = true
      return true
    } catch is CancellationError { return false }
    catch { self.error = error.localizedDescription; return false }
  }

  func cancelSignIn() { receiver?.cancel() }

  func select(_ uri: String?) async {
    currentURI = uri
    revision += 1
    let revision = revision
    let generation = authGeneration
    saved = nil
    guard connected, let uri, uri.hasPrefix("spotify:track:") else { return }
    do {
      let value = try await readSaved(uri)
      guard generation == authGeneration, currentURI == uri, self.revision == revision else { return }
      saved = value
      error = nil
    } catch is CancellationError { }
    catch { if currentURI == uri && !Task.isCancelled { self.error = error.localizedDescription } }
  }

  func toggle(_ uri: String) async {
    guard !saving, connected, currentURI == uri, let saved, uri.hasPrefix("spotify:track:") else { return }
    let desired = !saved
    let generation = authGeneration
    saving = true
    error = nil
    defer { saving = false }
    do {
      // Apply the action shown by the heart, even if Spotify changed since the last read.
      _ = try await request(path: "me/library", method: desired ? "PUT" : "DELETE", uri: uri)
      guard generation == authGeneration else { throw CancellationError() }
      let confirmed = try await readSaved(uri)
      guard generation == authGeneration else { throw CancellationError() }
      guard confirmed == desired else { throw failure("Spotify has not confirmed the change. Try again.") }
      if currentURI == uri { revision += 1; self.saved = confirmed }
    } catch is CancellationError { }
    catch { self.error = error.localizedDescription }
  }

  private func readSaved(_ uri: String) async throws -> Bool {
    let data = try await request(path: "me/library/contains", method: "GET", uri: uri)
    guard let value = try JSONDecoder().decode([Bool].self, from: data).first else {
      throw failure("Spotify did not return the saved-song state.")
    }
    return value
  }

  private func request(path: String, method: String, uri: String, retry: Bool = true) async throws -> Data {
    let generation = authGeneration
    guard connected, !connecting, var credentials else { throw failure("Connect Spotify to use the heart.") }
    if credentials.expires.timeIntervalSinceNow < 60 { credentials = try await refresh(credentials) }
    guard generation == authGeneration else { throw CancellationError() }
    var url = URLComponents(string: "https://api.spotify.com/v1/\(path)")!
    url.queryItems = [.init(name: "uris", value: uri)]
    var request = URLRequest(url: url.url!)
    request.httpMethod = method
    request.timeoutInterval = 20
    request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await session.data(for: request)
    guard generation == authGeneration else { throw CancellationError() }
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    if status == 401, retry {
      _ = try await refresh(credentials)
      return try await self.request(path: path, method: method, uri: uri, retry: false)
    }
    guard (200...299).contains(status) else {
      switch status {
      case 401: throw failure("Spotify sign-in expired. Connect again.")
      case 403: throw failure("Spotify denied library access. Check the app's test users and reconnect with library permission.")
      case 429: throw failure("Spotify received too many requests. Wait, then try again.")
      default: throw failure("Spotify could not update or read your library (\(status)). Try again.")
      }
    }
    return data
  }

  private func refresh(_ credentials: Credentials) async throws -> Credentials {
    if let refreshTask { return try await refreshTask.value }
    let generation = authGeneration
    let task = Task {
      let updated = try await token(clientID: credentials.clientID, fields: [
        "grant_type": "refresh_token", "refresh_token": credentials.refreshToken,
      ], refreshToken: credentials.refreshToken)
      try Task.checkCancellation()
      guard generation == self.authGeneration else { throw CancellationError() }
      try store(updated)
      self.credentials = updated
      return updated
    }
    refreshTask = task
    defer { if generation == authGeneration { refreshTask = nil } }
    return try await task.value
  }

  private func token(clientID: String, fields: [String: String], refreshToken: String? = nil) async throws -> Credentials {
    var fields = fields
    fields["client_id"] = clientID
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    let form = fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)" }
      .joined(separator: "&")
    var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
    request.httpMethod = "POST"
    request.httpBody = Data(form.utf8)
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 20
    let (data, response) = try await session.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw failure("Spotify sign-in failed. Check the client ID and return URL, then connect again.")
    }
    struct Reply: Decodable {
      let access_token: String
      let refresh_token: String?
      let expires_in: Double
    }
    let reply = try JSONDecoder().decode(Reply.self, from: data)
    guard let refresh = reply.refresh_token ?? refreshToken else { throw failure("Spotify did not return offline access. Connect again.") }
    return Credentials(clientID: clientID, accessToken: reply.access_token,
      refreshToken: refresh, expires: Date().addingTimeInterval(reply.expires_in))
  }

  private func store(_ credentials: Credentials) throws {
    let data = try JSONEncoder().encode(credentials)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: "account",
    ]
    let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var insertion = query
      insertion[kSecValueData as String] = data
      insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else { throw failure("Spotify sign-in could not be saved in Keychain.") }
    } else if status != errSecSuccess { throw failure("Spotify sign-in could not be updated in Keychain.") }
  }

  private func random() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw failure("Secure Spotify sign-in could not start.") }
    return base64URL(Data(bytes))
  }

  private func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }

  private func failure(_ message: String) -> NSError {
    NSError(domain: "MacIsland.Spotify", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
