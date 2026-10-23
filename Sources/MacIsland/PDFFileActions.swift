import Foundation
import PDFKit
import Quartz

enum PDFFileActions {
  static func convertImage(_ source: URL, folder: URL) throws -> URL {
    let image = try FileActions.decodeImage(source)
    let temporary = folder.appendingPathComponent(".mac-island-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: temporary) }
    var bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    guard let context = CGContext(temporary as CFURL, mediaBox: &bounds, nil)
    else { throw FileActions.failure("The PDF could not be created.") }
    context.beginPDFPage(nil)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(bounds)
    context.draw(image, in: bounds)
    context.endPDFPage()
    context.closePDF()
    guard PDFDocument(url: temporary)?.pageCount == 1 else {
      throw FileActions.failure("The PDF could not be saved.")
    }
    return try FileActions.publish(
      temporary, name: source.deletingPathExtension().lastPathComponent + ".pdf", folder: folder)
  }

  static func compress(_ source: URL, folder: URL) throws -> (URL?, String) {
    guard let document = PDFDocument(url: source), document.pageCount > 0 else {
      throw FileActions.failure("Use a readable PDF.")
    }
    guard !document.isEncrypted else {
      throw FileActions.failure("Encrypted PDFs cannot be compressed.")
    }
    guard let filter = QuartzFilter(url: URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter")) else {
      throw FileActions.failure("The macOS PDF compression filter is not available.")
    }
    let temporary = folder.appendingPathComponent(".mac-island-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: temporary) }
    guard document.write(to: temporary, withOptions: [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter]),
      let output = PDFDocument(url: temporary), output.pageCount == document.pageCount,
      output.string == document.string
    else { throw FileActions.failure("The PDF could not be compressed with its text and pages intact.") }
    let oldSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    let newSize = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard newSize > 0, newSize < oldSize else {
      return (nil, "\(source.lastPathComponent): no smaller PDF could be made. The source was kept.")
    }
    let file = try FileActions.publish(
      temporary, name: source.deletingPathExtension().lastPathComponent + "-compressed.pdf", folder: folder)
    let before = ByteCountFormatter.string(fromByteCount: Int64(oldSize), countStyle: .file)
    let after = ByteCountFormatter.string(fromByteCount: Int64(newSize), countStyle: .file)
    return (file, "\(source.lastPathComponent): \(before) → \(after).")
  }
}
