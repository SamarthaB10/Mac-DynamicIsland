import Foundation

enum ImageCompression {
  static func compress(_ source: URL, folder: URL, format: ImageOutput, maximumBytes: Int) throws -> (URL?, String) {
    guard maximumBytes > 0 else { throw FileActions.failure("Enter a positive target size.") }
    let sourceSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    let limit = min(maximumBytes, sourceSize - 1)
    guard limit > 0 else { throw FileActions.failure("The source image is empty.") }
    let temporary = folder.appendingPathComponent(".mac-island-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: temporary) }
    // Bound decoded memory even when the source has a very large pixel count.
    var edge = 8192
    while edge >= 1 {
      let outcome: (Int, Int) = try autoreleasepool {
        let image = try FileActions.decodeImage(source, maximum: edge)
        let actualEdge = max(image.width, image.height)
        let qualities = format == .jpeg ? [0.85, 0.65, 0.45, 0.25] : [1.0]
        var size = 0
        for quality in qualities {
          try FileActions.encodeImage(image, to: temporary, format: format, quality: quality)
          size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
          if size > 0, size <= limit { break }
        }
        return (size, actualEdge)
      }
      if outcome.0 > 0, outcome.0 <= limit {
        let name = source.deletingPathExtension().lastPathComponent + "-compressed.\(format.suffix)"
        let file = try FileActions.publish(temporary, name: name, folder: folder)
        let before = ByteCountFormatter.string(fromByteCount: Int64(sourceSize), countStyle: .file)
        let after = ByteCountFormatter.string(fromByteCount: Int64(outcome.0), countStyle: .file)
        return (file, "\(source.lastPathComponent): \(before) → \(after).")
      }
      guard outcome.1 > 1 else { break }
      let ratio = min(0.75, sqrt(Double(limit) / Double(max(1, outcome.0))) * 0.9)
      edge = max(1, Int(Double(outcome.1) * ratio))
    }
    return (nil, "\(source.lastPathComponent): the target size could not be reached. No result was kept. Try a larger target or JPEG output.")
  }
}
