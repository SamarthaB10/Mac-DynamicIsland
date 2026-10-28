import AppKit
import Combine

// Owns Hub file references and keeps temporary sources until their users finish.
@MainActor
final class HubFileStore: ObservableObject {
  @Published private(set) var files: [URL] = []
  @Published var selectedFiles: Set<URL> = []
  @Published var error: String?
  @Published private(set) var processing = false
  @Published private var onlineFiles: Set<URL> = []
  @Published private var drags: [URL: OutgoingDrag] = [:]
  @Published private var uploads: [URL: Int] = [:]
  var filesAdded: (() -> Void)?
  var dropFailed: ((String) -> Void)?
  private let preview = HubFilePreview()
  private let dropReceiver = HubDropReceiver()

  private struct OutgoingDrag {
    let id: UUID
    let promise: HubFilePromise
    var accepted = false
    var copied = false
  }

  init() {
    dropReceiver.addedFiles = { [weak self] urls, online in self?.add(urls, temporary: online) }
    dropReceiver.failed = { [weak self] message in self?.dropFailed?(message) }
  }

  var selected: [URL] { files.filter { selectedFiles.contains($0) } }
  var selectedOnlineFiles: [URL] { selected.filter { onlineFiles.contains($0) } }
  var canProcess: Bool { !processing && drags.isEmpty }

  func canRemove(_ url: URL) -> Bool {
    !processing && drags[url] == nil && uploads[url] == nil
  }

  func receive(_ pasteboard: NSPasteboard) -> Bool { dropReceiver.receive(pasteboard) }
  func cleanup() { dropReceiver.cleanup() }

  func add(_ urls: [URL], temporary: Bool = false) {
    var missing = false
    for url in urls where url.isFileURL {
      let canonical = url.standardizedFileURL
      guard FileManager.default.fileExists(atPath: canonical.path) else {
        missing = true
        continue
      }
      if temporary { onlineFiles.insert(canonical) }
      if !files.contains(canonical) { files.append(canonical) }
    }
    error = missing ? "A file is no longer available." : nil
    filesAdded?()
  }

  func showPreview(_ url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else {
      error = "This file was moved or deleted. Remove it from the Hub."
      return
    }
    preview.show(url)
  }

  func remove(_ url: URL) {
    guard canRemove(url) else {
      error = "Wait for the current file operation to finish."
      return
    }
    if onlineFiles.contains(url) {
      do { try FileManager.default.removeItem(at: url) } catch {
        let failure = error as NSError
        // Missing temporary files must not leave entries that cannot be removed.
        guard failure.domain == NSCocoaErrorDomain && failure.code == NSFileNoSuchFileError else {
          self.error =
            "The temporary online file could not be removed. \(error.localizedDescription)"
          return
        }
      }
      onlineFiles.remove(url)
    }
    preview.close(url)
    files.removeAll { $0 == url }
    selectedFiles.remove(url)
    error = nil
  }

  // The source stays protected for the full upload, including failure paths.
  func uploadFiles(_ urls: [URL], operation: @escaping () async throws -> Void) throws -> Task<
    Void, Error
  > {
    let sources = Set(urls.map(\.standardizedFileURL))
    guard sources.allSatisfy({ drags[$0] == nil }) else {
      throw FileActions.failure("Wait for the file drag to finish, then upload again.")
    }
    for url in sources { uploads[url, default: 0] += 1 }
    return Task {
      defer {
        for url in sources {
          if uploads[url] == 1 {
            uploads.removeValue(forKey: url)
          } else {
            uploads[url, default: 0] -= 1
          }
        }
      }
      try await operation()
    }
  }

  func beginProcessing() -> Bool {
    guard canProcess else { return false }
    processing = true
    error = nil
    return true
  }

  func finishProcessing() { processing = false }

  func dragWriter(for url: URL) -> NSPasteboardWriting {
    guard onlineFiles.contains(url) else { return url as NSURL }
    let id = UUID()
    let promise = HubFilePromise(url: url) { [weak self] error in
      guard let self, self.drags[url]?.id == id else { return }
      if let error {
        self.drags.removeValue(forKey: url)
        self.error = "The online file could not be delivered. \(error.localizedDescription)"
      } else {
        self.drags[url]?.copied = true
        self.finishDrag(url)
      }
    }
    drags[url] = OutgoingDrag(id: id, promise: promise)
    return promise.provider
  }

  func endDrag(_ url: URL, result: HubFileDragResult) {
    if onlineFiles.contains(url) {
      if result == .delivered {
        drags[url]?.accepted = true
        finishDrag(url)
      } else {
        drags.removeValue(forKey: url)
        if result == .discarded { remove(url) }
      }
    } else if result != .kept {
      remove(url)
    }
  }

  private func finishDrag(_ url: URL) {
    guard let drag = drags[url], drag.accepted, drag.copied else { return }
    drags.removeValue(forKey: url)
    remove(url)
  }
}
