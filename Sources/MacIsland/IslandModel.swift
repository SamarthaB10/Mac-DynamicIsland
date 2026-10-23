import AppKit
import Combine
import IslandCore

enum IslandTab: String, CaseIterable {
  case music = "Now Playing"
  case files = "Hub"
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
  @Published var hubView = HubSection.files
  @Published var selectedFiles: Set<URL> = []
  @Published private(set) var savedItems: [SavedItem] = []
  @Published var textInput = ""
  @Published var textError: String?
  @Published var actionReport: String?
  @Published private(set) var processingFiles = false
  private let textStore = SavedTextStore()
  private var textStoreLoaded = false
  @Published var fileError: String?
  @Published private(set) var dropTargeted = false
  @Published private(set) var isChoosingFiles = false {
    didSet { updateFileInteraction() }
  }
  var configuringImages = false {
    didSet { updateFileInteraction() }
  }
  private(set) var draggingFile = false
  let media = MediaController()
  let weather = WeatherController()
  let audio = AudioController()
  var updateInteraction: (() -> Void)?
  var openGoogleDrive: (() -> Void)?
  var openForKeyboard: (() -> Void)?
  weak var islandWindow: NSWindow?
  @Published private(set) var connectionNotice: String?
  private var noticeTask: Task<Void, Never>?
  private var audioSubscription: AnyCancellable?
  private let core = island_create()!
  private var collapseTask: Task<Void, Never>?
  private var scheduledDeadline: UInt64 = 0

  static let expandedSize = CGSize(width: 408, height: 216)
  static let hubSize = CGSize(width: 480, height: 360)
  var contentSize: CGSize {
    if tab == .files { return Self.hubSize }
    return CGSize(
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
      width: max(Self.hubSize.width, compactSize.width) + 48,
      height: Self.hubSize.height + notchHeight + 48)
  }
  static let canvasInset: CGFloat = 24

  var panelSize: CGSize {
    expanded
      ? CGSize(
        width: contentSize.width, height: contentSize.height + max(0, notchHeight - 6))
      : compactSize
  }

  init() {
    do {
      savedItems = try textStore.load()
      textStoreLoaded = true
    } catch { textError = "Saved Text could not be loaded. Existing data was kept. \(error.localizedDescription)" }
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

  private func updateFileInteraction() {
    send(isChoosingFiles || configuringImages || draggingFile ? 5 : 6)
  }

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
  func beginFileDrag() {
    draggingFile = true
    send(5)
  }
  func endFileDrag(_ url: URL, accepted: Bool) {
    if accepted { removeFile(url) }
    draggingFile = false
    updateFileInteraction()
  }
  func setDropTarget(_ targeted: Bool) {
    dropTargeted = targeted
    if targeted { tab = .files; hubView = .files }
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
    hubView = .files
    expand()
  }

  func chooseFiles() {
    isChoosingFiles = true
    let picker = NSOpenPanel()
    picker.allowsMultipleSelection = true
    picker.canChooseDirectories = true
    picker.prompt = "Add to Hub"
    NSApp.activate(ignoringOtherApps: true)
    presentPicker(picker) { [weak self] result in
      guard let self else { return }
      self.isChoosingFiles = false
      if result == .OK { self.addFiles(picker.urls) }
      self.openForKeyboard?()
    }
  }

  private func presentPicker(_ picker: NSOpenPanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
    if let islandWindow { picker.beginSheetModal(for: islandWindow, completionHandler: completion) }
    else { picker.begin(completionHandler: completion) }
  }

  func reveal(_ url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else {
      fileError = "This file was moved or deleted. Remove it from the Hub."
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  func removeFile(_ url: URL) {
    files.removeAll { $0 == url }
    selectedFiles.remove(url)
  }

  func saveText() {
    guard !textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    if persistText([SavedItem(id: UUID(), text: textInput)] + savedItems) { textInput = "" }
  }

  @discardableResult
  func pasteText() -> Bool {
    guard expanded, tab == .files, hubView == .savedText, !isChoosingFiles else { return false }
    guard let text = NSPasteboard.general.string(forType: .string) else {
      textError = "The clipboard does not contain text."
      return true
    }
    textInput += text
    saveText()
    return true
  }

  func removeText(_ item: SavedItem) {
    _ = persistText(savedItems.filter { $0.id != item.id })
  }

  private func persistText(_ items: [SavedItem]) -> Bool {
    guard textStoreLoaded else { return false }
    do {
      try textStore.save(items)
      savedItems = items
      textError = nil
      return true
    } catch {
      textError = "Saved Text could not be saved. \(error.localizedDescription)"
      return false
    }
  }

  func copyText(_ item: SavedItem) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(item.text, forType: .string)
  }

  func openText(_ item: SavedItem) {
    if let url = item.webURL { NSWorkspace.shared.open(url) }
  }

  func performFileAction(_ action: FileAction) {
    let sources = files.filter { selectedFiles.contains($0) }
    guard !sources.isEmpty, !processingFiles, !isChoosingFiles else { return }
    switch action {
    case .image, .imagePDF:
      let unsupported = FileActions.unsupportedImages(sources)
      if !unsupported.isEmpty {
        actionReport = "Select only PNG, JPEG, or HEIC images. Remove these items from the selection:\n"
          + unsupported.map(\.lastPathComponent).joined(separator: "\n")
        return
      }
    case .compressPDF:
      let unsupported = sources.filter {
        $0.pathExtension.lowercased() != "pdf" || (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
      }
      if !unsupported.isEmpty {
        actionReport = "Select only PDF files. Remove these items from the selection:\n"
          + unsupported.map(\.lastPathComponent).joined(separator: "\n")
        return
      }
    case .zip: break
    }
    isChoosingFiles = true
    let picker = NSOpenPanel()
    picker.title = "Choose an output folder"
    if case .compressPDF = action {
      picker.message = "PDF compression reduces image quality and keeps text selectable. Source files stay unchanged."
    }
    picker.prompt = "Use Folder"
    picker.canChooseFiles = false
    picker.canChooseDirectories = true
    picker.canCreateDirectories = true
    NSApp.activate(ignoringOtherApps: true)
    presentPicker(picker) { [weak self] response in
      guard let self else { return }
      guard response == .OK, let folder = picker.url else {
        self.isChoosingFiles = false
        self.openForKeyboard?()
        return
      }
      self.processingFiles = true
      self.fileError = nil
      Task {
        let result = await Task.detached(priority: .userInitiated) {
          FileActions.run(action, sources: sources, folder: folder)
        }.value
        self.addFiles(result.files)
        self.selectedFiles.subtract(sources)
        self.processingFiles = false
        self.isChoosingFiles = false
        self.openForKeyboard?()
        self.actionReport = "Added \(result.files.count) result file(s) to the Hub."
          + (result.notes.isEmpty ? "" : "\n" + result.notes.joined(separator: "\n"))
          + (result.failures.isEmpty ? "" : "\nFailed:\n" + result.failures.joined(separator: "\n"))
      }
    }
  }
}
