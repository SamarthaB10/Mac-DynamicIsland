import AppKit
import Combine
import Foundation

enum NotificationSource: String, Codable, CaseIterable, Identifiable {
  case x, linkedin, gmail, youtube
  var id: String { rawValue }
  var displayName: String {
    switch self {
    case .x: "X"
    case .linkedin: "LinkedIn"
    case .gmail: "Gmail"
    case .youtube: "YouTube"
    }
  }
  var symbol: String {
    switch self {
    case .x: "text.bubble"
    case .linkedin: "person.2"
    case .gmail: "envelope"
    case .youtube: "play.rectangle"
    }
  }
  var homeURL: URL {
    switch self {
    case .x: URL(string: "https://x.com")!
    case .linkedin: URL(string: "https://www.linkedin.com")!
    case .gmail: URL(string: "https://mail.google.com")!
    case .youtube: URL(string: "https://www.youtube.com")!
    }
  }
  init?(origin: String) {
    guard let url = URL(string: origin), url.scheme?.lowercased() == "https",
      url.user == nil, url.password == nil, url.port == nil,
      (url.path.isEmpty || url.path == "/"), url.query == nil, url.fragment == nil,
      let host = url.host?.lowercased()
    else { return nil }
    switch host {
    case "x.com", "www.x.com": self = .x
    case "linkedin.com", "www.linkedin.com": self = .linkedin
    case "mail.google.com": self = .gmail
    case "youtube.com", "www.youtube.com": self = .youtube
    default: return nil
    }
  }
}

struct IslandNotification: Codable, Identifiable {
  let id: UUID
  let source: NotificationSource
  let title: String
  let body: String
  let receivedAt: Date
  var isRead: Bool
  let originalURL: URL?
  var openLabel: String { originalURL == nil ? "Open \(source.displayName)" : "Open page" }
}

struct NotificationSyncNotice: Codable, Identifiable {
  let id: UUID
  let title: String
  let detail: String
}

@MainActor
final class IslandNotificationStore: ObservableObject {
  @Published private(set) var items: [IslandNotification] = []
  @Published private(set) var notices: [NotificationSyncNotice] = []
  @Published private(set) var arrivalSequence = 0
  @Published private(set) var isConnected = false
  @Published private(set) var connectionMessage = "Connect to Ardia to receive notifications."
  @Published private(set) var persistenceError: String?
  @Published private(set) var enabledSources = Set(NotificationSource.allCases)
  var unreadCount: Int { items.filter { !$0.isRead }.count }

  private struct SavedState: Codable {
    var items: [IslandNotification]
    var notices: [NotificationSyncNotice]
    var enabledSources: Set<NotificationSource>
    var connectionEnabled: Bool
  }
  private let fileURL: URL
  private var connectionEnabled = false
  private var canSave = true
  private var connection: ArdiaNotificationConnection?
  private var connectionID = UUID()

  init() {
    fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Mac Island", isDirectory: true)
      .appendingPathComponent("Notifications.json")
    if FileManager.default.fileExists(atPath: fileURL.path) {
      do {
        let state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: fileURL))
        items = state.items
        notices = state.notices
        enabledSources = state.enabledSources
        connectionEnabled = state.connectionEnabled
      } catch {
        canSave = false
        persistenceError = "Could not read saved notifications. The existing file will not be replaced: \(error.localizedDescription)"
      }
    }
    if !notices.isEmpty { noteLocalOnlyAction() }
    if connectionEnabled { startConnection() }
  }

  func setEnabled(_ source: NotificationSource, enabled: Bool) {
    if enabled { enabledSources.insert(source) } else { enabledSources.remove(source) }
    save()
  }

  func connect() {
    connectionEnabled = true
    save()
    startConnection()
  }

  func disconnect() {
    connectionEnabled = false
    connectionID = UUID()
    connection?.stop()
    connection = nil
    isConnected = false
    connectionMessage = "Disconnected from Ardia."
    save()
  }

  func markRead(_ item: IslandNotification) {
    guard let index = items.firstIndex(where: { $0.id == item.id }), !items[index].isRead else { return }
    items[index].isRead = true
    noteLocalOnlyAction()
    save()
  }

  func dismiss(_ item: IslandNotification) {
    guard items.contains(where: { $0.id == item.id }) else { return }
    items.removeAll { $0.id == item.id }
    noteLocalOnlyAction()
    save()
  }

  func dismissAll() {
    guard !items.isEmpty else { return }
    items.removeAll()
    noteLocalOnlyAction()
    save()
  }

  func open(_ item: IslandNotification) {
    guard let browser = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.ardia.browser") else {
      connectionMessage = "Could not find Ardia to open \(item.source.displayName)."
      return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.open([item.originalURL ?? item.source.homeURL], withApplicationAt: browser, configuration: configuration) { [weak self] _, error in
      Task { @MainActor in
        guard let self else { return }
        if let error { self.connectionMessage = "Could not open Ardia: \(error.localizedDescription)" }
        else if item.originalURL != nil { self.markRead(item) }
      }
    }
  }

  func clearNotice(_ notice: NotificationSyncNotice) {
    notices.removeAll { $0.id == notice.id }
    save()
  }

  private func noteLocalOnlyAction() {
    notices = [NotificationSyncNotice(id: notices.first?.id ?? UUID(), title: "Website actions are not connected",
      detail: "Read and dismiss changed Mac Island only. Website read state and macOS alerts are unchanged.")]
  }

  private func startConnection() {
    guard connection == nil else { return }
    let id = UUID()
    connectionID = id
    let bridge = ArdiaNotificationConnection(onEvent: { [weak self] event in
      Task { @MainActor in
        guard let self, self.connectionID == id, self.isConnected,
          let source = NotificationSource(origin: event.data.origin), self.enabledSources.contains(source)
        else { return }
        self.items.insert(IslandNotification(id: UUID(), source: source, title: event.data.title,
          body: event.data.body, receivedAt: Date(timeIntervalSince1970: event.time / 1000),
          isRead: false, originalURL: nil), at: 0)
        self.arrivalSequence += 1
        self.save()
      }
    }, onExit: { [weak self] message in
      Task { @MainActor in
        guard let self, self.connectionID == id else { return }
        self.connection = nil
        self.isConnected = false
        self.connectionMessage = message
      }
    })
    do {
      try bridge.start()
      connection = bridge
      isConnected = true
      connectionMessage = "Connected to Ardia."
    } catch {
      isConnected = false
      connectionMessage = "Could not connect to Ardia: \(error.localizedDescription)"
    }
  }

  private func save() {
    guard canSave else { return }
    do {
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let state = SavedState(items: items, notices: notices, enabledSources: enabledSources, connectionEnabled: connectionEnabled)
      try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
      persistenceError = nil
    } catch {
      persistenceError = "Could not save notifications: \(error.localizedDescription)"
    }
  }
}
