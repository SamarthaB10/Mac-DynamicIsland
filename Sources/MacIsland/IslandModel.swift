import AppKit
import Combine
import IslandCore

enum IslandTab: String, CaseIterable {
  case music = "Now Playing"
  case files = "File Tray"
  case devices = "Devices"
}

@MainActor
final class IslandModel: ObservableObject {
  @Published private(set) var expanded = false
  @Published private(set) var visible = true
  @Published var notchWidth: CGFloat = 0
  @Published var notchHeight: CGFloat = 0
  @Published private(set) var pinned = false
  @Published var tab = IslandTab.music
  @Published var files: [URL] = []
  @Published var fileError: String?
  @Published private(set) var isChoosingFiles = false
  let media = MediaController()
  let weather = WeatherController()
  let audio = AudioController()
  var updateInteraction: (() -> Void)?
  var openGoogleDrive: (() -> Void)?
  var openForKeyboard: (() -> Void)?
  @Published private(set) var connectionNotice: String?
  private var noticeTask: Task<Void, Never>?
  private var audioSubscription: AnyCancellable?
  private let core = island_create()!
  private var collapseTask: Task<Void, Never>?
  private var scheduledDeadline: UInt64 = 0

  static let expandedSize = CGSize(width: 408, height: 216)
  var contentSize: CGSize {
    CGSize(
      width: Self.expandedSize.width,
      height: tab == .devices
        ? min(192, max(132, CGFloat(audio.outputs.count + audio.displays.count) * 34 + 60))
        : Self.expandedSize.height)
  }
  var compactSize: CGSize {
    CGSize(
      width: notchWidth > 0 ? notchWidth + 88 : 248, height: notchHeight > 0 ? notchHeight : 36)
  }
  var canvasSize: CGSize {
    CGSize(
      width: max(Self.expandedSize.width, compactSize.width) + 48,
      height: Self.expandedSize.height + notchHeight + 48)
  }
  static let canvasInset: CGFloat = 24

  var panelSize: CGSize {
    expanded
      ? CGSize(
        width: contentSize.width, height: contentSize.height + max(0, notchHeight - 6))
      : compactSize
  }

  init() {
    if UserDefaults.standard.bool(forKey: "islandHidden") { send(11) }
    audioSubscription = audio.$name.removeDuplicates().dropFirst()
      .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
      .sink { [weak self] name in
        guard let self else { return }
        self.connectionNotice = name
        self.noticeTask?.cancel()
        self.noticeTask = Task { [weak self] in
          try? await Task.sleep(for: .seconds(3))
          guard !Task.isCancelled else { return }
          self?.connectionNotice = nil
        }
      }
  }

  deinit {
    collapseTask?.cancel()
    noticeTask?.cancel()
    island_destroy(core)
  }

  private var now: UInt64 { DispatchTime.now().uptimeNanoseconds / 1_000_000 }

  // Rust owns open/close policy. Swift schedules only its next requested deadline.
  private func send(_ event: UInt32) {
    let snapshot = island_event(core, event, now)
    let visibilityChanged = visible != (snapshot.visible != 0)
    if visibilityChanged { visible = snapshot.visible != 0 }
    let sizeChanged = expanded != (snapshot.expanded != 0)
    if sizeChanged { expanded = snapshot.expanded != 0 }
    if pinned != (snapshot.pinned != 0) { pinned = snapshot.pinned != 0 }
    if scheduledDeadline != snapshot.deadline_ms {
      scheduledDeadline = snapshot.deadline_ms
      collapseTask?.cancel()
      if snapshot.deadline_ms != 0 {
        let delay = snapshot.deadline_ms > now ? snapshot.deadline_ms - now : 0
        collapseTask = Task { [weak self] in
          try? await Task.sleep(for: .milliseconds(delay))
          guard !Task.isCancelled else { return }
          self?.send(10)
        }
      }
    }
    if sizeChanged || visibilityChanged { updateInteraction?() }
  }

  func setVisible(_ show: Bool) {
    UserDefaults.standard.set(!show, forKey: "islandHidden")
    send(show ? 12 : 11)
  }
  func expand() { send(0) }
  func collapse(force: Bool = false) { send(force ? 4 : 9) }
  func hover(_ inside: Bool) { send(inside ? 1 : 2) }
  func togglePin() { send(3) }
  func setDropTarget(_ targeted: Bool) {
    if targeted { tab = .files }
    send(targeted ? 7 : 8)
  }

  func addFiles(_ urls: [URL]) {
    var missing = false
    for url in urls where url.isFileURL {
      let canonical = url.standardizedFileURL
      guard FileManager.default.fileExists(atPath: canonical.path) else {
        missing = true
        continue
      }
      if !files.contains(canonical) { files.append(canonical) }
    }
    fileError = missing ? "A file is no longer available." : nil
    tab = .files
    expand()
  }

  func chooseFiles() {
    isChoosingFiles = true
    send(5)
    let picker = NSOpenPanel()
    picker.allowsMultipleSelection = true
    picker.canChooseDirectories = true
    picker.prompt = "Add to Tray"
    NSApp.activate(ignoringOtherApps: true)
    picker.begin { [weak self] result in
      guard let self else { return }
      self.isChoosingFiles = false
      self.send(6)
      if result == .OK { self.addFiles(picker.urls) }
      self.openForKeyboard?()
    }
  }

  func reveal(_ url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else {
      fileError = "This file was moved or deleted. Remove it from the tray."
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
}
