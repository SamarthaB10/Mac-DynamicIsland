import AppKit

@MainActor
final class HubDropReceiver {
  var addedFiles: (([URL], Bool) -> Void)?
  var failed: ((String) -> Void)?
  private let promiseQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    return queue
  }()
  private let sessionFolder = FileManager.default.temporaryDirectory
    .appendingPathComponent("Mac Island Online Drops/\(UUID().uuidString)")
  private let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    return URLSession(configuration: configuration)
  }()

  static let types = [NSPasteboard.PasteboardType.fileURL, .URL, .png, .tiff]
    + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

  static func canRead(_ pasteboard: NSPasteboard) -> Bool {
    !(Set(pasteboard.types ?? []).intersection(types).isEmpty)
  }

  func receive(_ pasteboard: NSPasteboard) -> Bool {
    let local = pasteboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    if !local.isEmpty { addedFiles?(local, false); return true }
    do {
      let folder = try downloadsFolder()
      let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? []
      if !promises.isEmpty {
        for promise in promises {
          // Each promise gets its own folder so a browser cannot replace an earlier download.
          let destination = folder.appendingPathComponent(UUID().uuidString)
          try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
          promise.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: promiseQueue) {
            [weak self] url, error in
            Task { @MainActor in
              if let error { self?.failed?("The browser file could not be added. \(error.localizedDescription)") }
              else { self?.addedFiles?([url], true) }
            }
          }
        }
        return true
      }
      if let png = pasteboard.data(forType: .png) {
        try saveImage(png, folder: folder)
        return true
      }
      if let tiff = pasteboard.data(forType: .tiff), let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:]) {
        try saveImage(png, folder: folder)
        return true
      }
      let urls = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? [])
        .filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
      guard !urls.isEmpty else { return false }
      Task {
        var completed: [URL] = []
        var failures: [String] = []
        for url in urls {
          do {
            let (temporary, response) = try await session.download(from: url)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
              throw FileActions.failure("The website did not return a downloadable file.")
            }
            let proposed = response.suggestedFilename ?? url.lastPathComponent
            let name = URL(fileURLWithPath: proposed).lastPathComponent
            let safeName = ["", ".", "..", "/"].contains(name) ? "Download" : name
            let result = try await Task.detached(priority: .userInitiated) {
              try FileActions.publish(temporary, name: safeName, folder: folder)
            }.value
            completed.append(result)
          } catch { failures.append("A browser download failed. \(error.localizedDescription)") }
        }
        if !completed.isEmpty { addedFiles?(completed, true) }
        if !failures.isEmpty { failed?(failures.joined(separator: "\n")) }
      }
      return true
    } catch {
      failed?("The dropped file could not be saved. \(error.localizedDescription)")
      return false
    }
  }

  private func downloadsFolder() throws -> URL {
    let folder = sessionFolder
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  private func saveImage(_ data: Data, folder: URL) throws {
    let temporary = folder.appendingPathComponent(".mac-island-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: temporary) }
    try data.write(to: temporary, options: .withoutOverwriting)
    addedFiles?([try FileActions.publish(temporary, name: "Image.png", folder: folder)], true)
  }

  func cleanup() { try? FileManager.default.removeItem(at: sessionFolder) }
}
