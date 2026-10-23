import Foundation
import Darwin
import ImageIO
import UniformTypeIdentifiers

enum ImageOutput: String, CaseIterable {
  case png = "PNG"
  case jpeg = "JPEG"

  var type: UTType { self == .png ? .png : .jpeg }
  var suffix: String { self == .png ? "png" : "jpg" }
}

enum FileAction {
  case zip
  case image(format: ImageOutput, maximumLongEdge: Int?)
  case imagePDF
  case compressPDF
}

struct FileActionResult {
  var files: [URL] = []
  var failures: [String] = []
  var notes: [String] = []
}

// File work runs outside the main actor. Each output is published only after it is complete.
enum FileActions {
  static func unsupportedImages(_ urls: [URL]) -> [URL] {
    urls.filter { url in
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let type = CGImageSourceGetType(source)
      else { return true }
      return ![UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier]
        .contains(type as String)
    }
  }

  static func run(_ action: FileAction, sources: [URL], folder: URL) -> FileActionResult {
    switch action {
    case .zip: return archive(sources, folder: folder)
    case .image, .imagePDF, .compressPDF:
      var result = FileActionResult()
      for source in sources {
        do {
          try autoreleasepool {
            switch action {
            case .image(let format, let maximum):
              result.files.append(try image(source, folder: folder, format: format, maximum: maximum))
            case .imagePDF:
              result.files.append(try PDFFileActions.convertImage(source, folder: folder))
            case .compressPDF:
              let (file, note) = try PDFFileActions.compress(source, folder: folder)
              if let file { result.files.append(file) }
              result.notes.append(note)
            case .zip: break
            }
          }
        } catch { result.failures.append("\(source.lastPathComponent): \(error.localizedDescription)") }
      }
      return result
    }
  }

  private static func archive(_ sources: [URL], folder: URL) -> FileActionResult {
    var result = FileActionResult()
    let manager = FileManager.default
    let workspace = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let contents = workspace.appendingPathComponent("Contents")
    do {
      try manager.createDirectory(at: contents, withIntermediateDirectories: true)
      defer { try? manager.removeItem(at: workspace) }
      var copied = 0
      for source in sources {
        do {
          let resolved = source.resolvingSymlinksInPath().standardizedFileURL.path
          let destination = folder.resolvingSymlinksInPath().standardizedFileURL.path
          if destination == resolved || destination.hasPrefix(resolved + "/") {
            throw failure("Choose an output folder outside the selected folders.")
          }
          var index = 1
          var target = availableName(source.lastPathComponent, in: contents)
          while manager.fileExists(atPath: target.path) {
            index += 1
            target = availableName(source.lastPathComponent, in: contents, index: index)
          }
          do { try manager.copyItem(at: source, to: target) }
          catch {
            try? manager.removeItem(at: target)
            throw error
          }
          copied += 1
        } catch { result.failures.append("\(source.lastPathComponent): \(error.localizedDescription)") }
      }
      guard copied > 0 else { return result }
      let temporary = workspace.appendingPathComponent("Archive.zip")
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
      process.arguments = ["-c", "-k", "--sequesterRsrc", contents.path, temporary.path]
      let errorFile = workspace.appendingPathComponent("ditto-error.txt")
      manager.createFile(atPath: errorFile.path, contents: nil)
      let errorHandle = try FileHandle(forWritingTo: errorFile)
      defer { try? errorHandle.close() }
      process.standardError = errorHandle
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        let detail = (try? String(contentsOf: errorFile, encoding: .utf8)) ?? ""
        throw failure("ZIP creation failed. \(detail)")
      }
      let name = sources.count == 1 ? sources[0].deletingPathExtension().lastPathComponent : "Archive"
      result.files.append(try publish(temporary, name: name + ".zip", folder: folder))
    } catch { result.failures.append(error.localizedDescription) }
    return result
  }

  private static func image(_ url: URL, folder: URL, format: ImageOutput, maximum: Int?) throws -> URL {
    var image = try decodeImage(url, maximum: maximum)
    if format == .jpeg {
      guard let context = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
      else { throw failure("The image could not be prepared.") }
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
      context.fill(bounds)
      context.draw(image, in: bounds)
      guard let flattened = context.makeImage() else { throw failure("JPEG conversion failed.") }
      image = flattened
    }
    let temporary = folder.appendingPathComponent(".mac-island-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: temporary) }
    guard let destination = CGImageDestinationCreateWithURL(
      temporary as CFURL, format.type.identifier as CFString, 1, nil)
    else { throw failure("The output folder cannot be written.") }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw failure("The image could not be saved.") }
    let tag = maximum == nil ? "converted" : "resized"
    let name = url.deletingPathExtension().lastPathComponent + "-\(tag).\(format.suffix)"
    return try publish(temporary, name: name, folder: folder)
  }

  static func decodeImage(_ url: URL, maximum: Int? = nil) throws -> CGImage {
    guard unsupportedImages([url]).isEmpty,
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0
    else { throw failure("Use a readable PNG, JPEG, or HEIC image.") }
    let edge = min(maximum ?? max(width, height), max(width, height))
    guard edge > 0 else { throw failure("Enter a positive maximum long edge.") }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: edge,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { throw failure("The image could not be decoded.") }
    return image
  }

  private static func availableName(_ name: String, in folder: URL, index: Int = 1) -> URL {
    let original = folder.appendingPathComponent(name)
    if index == 1 { return original }
    let suffix = original.pathExtension
    let stem = original.deletingPathExtension().lastPathComponent
    return folder.appendingPathComponent("\(stem) \(index)" + (suffix.isEmpty ? "" : ".\(suffix)"))
  }

  static func publish(_ temporary: URL, name: String, folder: URL) throws -> URL {
    let manager = FileManager.default
    // ZIP staging can be on another volume. Copy into this folder before publishing.
    let local = folder.appendingPathComponent(".mac-island-\(UUID().uuidString)")
    defer { try? manager.removeItem(at: local) }
    try manager.copyItem(at: temporary, to: local)
    var index = 1
    while true {
      let target = availableName(name, in: folder, index: index)
      if renamex_np(local.path, target.path, UInt32(RENAME_EXCL)) == 0 { return target }
      let code = errno
      if code == EEXIST { index += 1 }
      else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
    }
  }

  static func failure(_ message: String) -> NSError {
    NSError(domain: "MacIsland.FileActions", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
