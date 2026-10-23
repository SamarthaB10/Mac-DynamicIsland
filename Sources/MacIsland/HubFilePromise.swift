import AppKit
import UniformTypeIdentifiers

// A receiving app gets its own file before the temporary online source is removed.
final class HubFilePromise: NSObject, NSFilePromiseProviderDelegate {
  let url: URL
  private let completed: (Error?) -> Void
  private let queue: OperationQueue = {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    return queue
  }()
  lazy var provider = NSFilePromiseProvider(
    fileType: UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.data.identifier,
    delegate: self)

  init(url: URL, completed: @escaping (Error?) -> Void) {
    self.url = url
    self.completed = completed
  }

  func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
    url.lastPathComponent
  }

  func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { queue }

  func filePromiseProvider(
    _ filePromiseProvider: NSFilePromiseProvider, writePromiseTo target: URL,
    completionHandler: @escaping (Error?) -> Void
  ) {
    var failure: Error?
    do { try FileManager.default.copyItem(at: url, to: target) }
    catch { failure = error }
    completionHandler(failure)
    DispatchQueue.main.async { [self] in completed(failure) }
  }
}
