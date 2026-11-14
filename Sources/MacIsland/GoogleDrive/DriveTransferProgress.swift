import Foundation

// Each transfer has its own delegate. Unknown server totals stay unknown.
final class DriveTransferProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  private let report: @Sendable (Int64, Int64) -> Void

  init(report: @escaping @Sendable (Int64, Int64) -> Void) { self.report = report }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64, totalBytesExpectedToSend: Int64
  ) {
    report(totalBytesSent, totalBytesExpectedToSend)
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    report(totalBytesWritten, totalBytesExpectedToWrite)
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
  ) {}
}
