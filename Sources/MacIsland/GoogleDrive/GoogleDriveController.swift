import AppKit
import UniformTypeIdentifiers

struct DriveFile: Decodable, Identifiable {
  struct Capabilities: Decodable { let canDownload: Bool? }
  let id: String
  let name: String
  let mimeType: String
  let capabilities: Capabilities?
  var folder: Bool { mimeType == "application/vnd.google-apps.folder" }
  var export: (mime: String, suffix: String)? {
    switch mimeType {
    case "application/vnd.google-apps.document":
      return ("application/vnd.openxmlformats-officedocument.wordprocessingml.document", "docx")
    case "application/vnd.google-apps.spreadsheet":
      return ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "xlsx")
    case "application/vnd.google-apps.presentation":
      return ("application/vnd.openxmlformats-officedocument.presentationml.presentation", "pptx")
    case "application/vnd.google-apps.drawing": return ("application/pdf", "pdf")
    default: return nil
    }
  }
}

struct DriveAccount: Codable, Identifiable {
  let id: String
  let email: String
  let name: String
  var tokens: GoogleTokens
}

@MainActor
final class GoogleDriveController: ObservableObject {
  @Published private(set) var configured = false
  @Published private(set) var accounts: [DriveAccount] = []
  @Published var selectedAccount: String?
  @Published private(set) var files: [DriveFile] = []
  @Published private(set) var folders: [(id: String, name: String)] = [("root", "My Drive")]
  @Published private(set) var busy = false
  @Published private(set) var status = ""
  @Published private(set) var error: String?
  @Published private(set) var nextPage: String?
  var receivedFile: ((URL) -> Void)?
  private let hubFiles: HubFileStore
  private var configuration: GoogleClientConfiguration?
  private let oauth = GoogleOAuth()
  private let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.timeoutIntervalForResource = 3600
    return URLSession(configuration: configuration)
  }()

  init(hubFiles: HubFileStore) {
    self.hubFiles = hubFiles
    do {
      configuration = try DriveKeychain.read("configuration", as: GoogleClientConfiguration.self)
      accounts = try DriveKeychain.read("accounts", as: [DriveAccount].self) ?? []
      selectedAccount = accounts.first?.id
      configured = configuration != nil
    } catch { self.error = error.localizedDescription }
  }

  func importConfiguration() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.message =
      "Choose the Desktop app OAuth JSON downloaded from Google Cloud. It will be stored in Keychain."
    panel.prompt = "Import"
    panel.begin { [weak self] result in
      guard result == .OK, let self, let url = panel.url else { return }
      do {
        guard self.accounts.isEmpty else {
          throw DriveFailure.message("Disconnect accounts before changing the OAuth client.")
        }
        struct File: Decodable {
          struct Installed: Decodable {
            let client_id: String
            let client_secret: String
          }
          let installed: Installed
        }
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(File.self, from: data).installed
        guard file.client_id.hasSuffix(".apps.googleusercontent.com"), !file.client_secret.isEmpty
        else { throw DriveFailure.message("Choose a valid Desktop app OAuth client JSON.") }
        let config = GoogleClientConfiguration(
          clientID: file.client_id, clientSecret: file.client_secret)
        try DriveKeychain.write(config, key: "configuration")
        self.configuration = config
        self.configured = true
        self.error = nil
        self.status = "Google sign-in is ready. Select Connect Account."
      } catch { self.error = error.localizedDescription }
    }
  }

  func connect() {
    guard !busy else { return }
    guard let configuration else {
      importConfiguration()
      return
    }
    run("Waiting for Google sign-in…") {
      let tokens = try await self.oauth.connect(configuration)
      let account = try await self.identity(tokens)
      var updated = self.accounts.filter { $0.id != account.id }
      updated.append(account)
      try DriveKeychain.write(updated, key: "accounts")
      self.accounts = updated
      self.selectedAccount = account.id
      self.files = []
      self.folders = [("root", "My Drive")]
      self.status = "Connected \(account.email)."
    }
  }

  func cancelSignIn() { oauth.cancel() }

  func disconnect() {
    guard let id = selectedAccount, !busy else { return }
    do {
      let remaining = accounts.filter { $0.id != id }
      try DriveKeychain.write(remaining, key: "accounts")
      accounts = remaining
      selectedAccount = accounts.first?.id
      files = []
      folders = [("root", "My Drive")]
      status = "Account disconnected on this Mac."
    } catch { self.error = error.localizedDescription }
  }

  func changeAccount() {
    folders = [("root", "My Drive")]
    files = []
    list()
  }
  func open(_ folder: DriveFile) {
    folders.append((folder.id, folder.name))
    list()
  }
  func back() {
    if folders.count > 1 {
      folders.removeLast()
      list()
    }
  }

  func list(search: String = "", more: Bool = false) {
    guard selectedAccount != nil, !busy else { return }
    let folder = folders.last!.id
    let page = more ? nextPage : nil
    run("Loading Drive files…") {
      let token = try await self.token()
      var query = "trashed = false"
      if search.isEmpty {
        query += " and '\(folder)' in parents"
      } else {
        query +=
          " and name contains '\(search.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'"))'"
      }
      var url = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
      url.queryItems = [
        .init(name: "q", value: query), .init(name: "pageSize", value: "100"),
        .init(name: "orderBy", value: "folder,name"),
        .init(
          name: "fields", value: "nextPageToken,files(id,name,mimeType,capabilities(canDownload))"),
        .init(name: "supportsAllDrives", value: "true"),
        .init(name: "includeItemsFromAllDrives", value: "true"),
      ]
      if let page { url.queryItems?.append(.init(name: "pageToken", value: page)) }
      let data = try await self.data(url.url!, token: token)
      struct Reply: Decodable {
        let files: [DriveFile]
        let nextPageToken: String?
      }
      let reply = try JSONDecoder().decode(Reply.self, from: data)
      self.files = more ? self.files + reply.files : reply.files
      self.nextPage = reply.nextPageToken
      self.status = "\(self.files.count) files"
    }
  }

  func download(_ file: DriveFile) {
    guard !busy, !file.folder else { return }
    if file.capabilities?.canDownload == false {
      error = "The owner does not allow this file to be downloaded."
      return
    }
    run("Downloading \(file.name)…") {
      let token = try await self.token()
      let address: URL
      var name = file.name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(
        of: ":", with: "_")
      if name == "." || name == ".." || name.isEmpty { name = "Drive file" }
      if let export = file.export {
        var url = URLComponents(
          string: "https://www.googleapis.com/drive/v3/files/\(file.id)/export")!
        url.queryItems = [.init(name: "mimeType", value: export.mime)]
        address = url.url!
        name += ".\(export.suffix)"
      } else {
        guard !file.mimeType.hasPrefix("application/vnd.google-apps.") else {
          throw DriveFailure.message(
            "This Google file type cannot be exported here. Open it in Google Drive.")
        }
        address = URL(
          string:
            "https://www.googleapis.com/drive/v3/files/\(file.id)?alt=media&supportsAllDrives=true")!
      }
      var request = URLRequest(url: address)
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      let (temporary, response) = try await self.session.download(for: request)
      try self.check(response)
      let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
        0
      ]
      .appendingPathComponent("Mac Island/Drive Downloads/\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let destination = folder.appendingPathComponent(name)
      try FileManager.default.moveItem(at: temporary, to: destination)
      self.receivedFile?(destination)
      self.status = "Added \(name) to Hub."
    }
  }

  func upload(_ urls: [URL]) {
    guard !busy, selectedAccount != nil, !urls.isEmpty else { return }
    let folder = folders.last!.id
    do {
      let upload = try hubFiles.uploadFiles(urls) {
        let token = try await self.token()
        for url in urls {
          let values = try url.resourceValues(forKeys: [
            .isRegularFileKey, .fileSizeKey, .contentTypeKey,
          ])
          guard values.isRegularFile == true else {
            throw DriveFailure.message("Upload files individually. Folder upload is not supported.")
          }
          var start = URLRequest(
            url: URL(
              string:
                "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&supportsAllDrives=true"
            )!)
          start.httpMethod = "POST"
          start.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
          start.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
          start.setValue(
            values.contentType?.preferredMIMEType ?? "application/octet-stream",
            forHTTPHeaderField: "X-Upload-Content-Type")
          start.setValue(String(values.fileSize ?? 0), forHTTPHeaderField: "X-Upload-Content-Length")
          start.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": url.lastPathComponent, "parents": [folder],
          ])
          let (_, response) = try await self.session.data(for: start)
          try self.check(response)
          guard let address = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location"),
            let sessionURL = URL(string: address), sessionURL.scheme == "https",
            sessionURL.host?.hasSuffix(".googleapis.com") == true
          else { throw DriveFailure.message("Google did not return a valid upload session.") }
          var upload = URLRequest(url: sessionURL)
          upload.httpMethod = "PUT"
          upload.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
          upload.setValue(
            values.contentType?.preferredMIMEType ?? "application/octet-stream",
            forHTTPHeaderField: "Content-Type")
          let (_, uploadResponse) = try await self.session.upload(for: upload, fromFile: url)
          try self.check(uploadResponse)
          self.status = "Uploaded \(url.lastPathComponent)."
        }
      }
      run("Uploading to Google Drive…") { try await upload.value }
    } catch { self.error = error.localizedDescription }
  }

  private func run(_ message: String, operation: @escaping () async throws -> Void) {
    busy = true
    error = nil
    status = message
    Task {
      defer { busy = false }
      do { try await operation() } catch is CancellationError { status = "Cancelled." } catch {
        self.error = error.localizedDescription
        status = ""
      }
    }
  }

  private func token() async throws -> String {
    guard let id = selectedAccount, let index = accounts.firstIndex(where: { $0.id == id }),
      let configuration
    else { throw DriveFailure.message("Connect a Google account first.") }
    if accounts[index].tokens.expires.timeIntervalSinceNow < 60 {
      let tokens = try await oauth.refresh(accounts[index].tokens, configuration: configuration)
      accounts[index].tokens = tokens
      try DriveKeychain.write(accounts, key: "accounts")
    }
    return accounts[index].tokens.accessToken
  }

  private func identity(_ tokens: GoogleTokens) async throws -> DriveAccount {
    let data = try await data(
      URL(
        string:
          "https://www.googleapis.com/drive/v3/about?fields=user(displayName,emailAddress,permissionId)"
      )!, token: tokens.accessToken)
    struct Reply: Decodable {
      struct User: Decodable {
        let displayName: String
        let emailAddress: String
        let permissionId: String
      }
      let user: User
    }
    let user = try JSONDecoder().decode(Reply.self, from: data).user
    return DriveAccount(
      id: user.permissionId, email: user.emailAddress, name: user.displayName, tokens: tokens)
  }

  private func data(_ url: URL, token: String) async throws -> Data {
    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await session.data(for: request)
    try check(response)
    return data
  }

  private func check(_ response: URLResponse) throws {
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
      if status == 401 {
        throw DriveFailure.message(
          "Google access expired. Disconnect this account, then reconnect.")
      }
      if status == 403 {
        throw DriveFailure.message(
          "Google refused this action. Check Drive API access, file permissions, and available storage."
        )
      }
      throw DriveFailure.message("Google Drive request failed (HTTP \(status)). Try again.")
    }
  }
}
