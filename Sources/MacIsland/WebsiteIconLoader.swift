import AppKit
import Foundation

/// Loads a site's HTML icon, with a conventional favicon as the fallback.
@MainActor
final class WebsiteIconLoader {
  static let shared = WebsiteIconLoader()
  private let cache = NSCache<NSURL, NSImage>()
  private let session: URLSession

  private init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 8
    configuration.timeoutIntervalForResource = 12
    configuration.httpCookieStorage = nil
    session = URLSession(configuration: configuration)
    cache.countLimit = 64
    cache.totalCostLimit = 4 * 1024 * 1024
  }

  func image(for page: URL) async -> NSImage? {
    if let image = cache.object(forKey: page as NSURL) { return image }
    var candidates: [URL] = []
    var fallbackPage = page
    if let (data, responseURL) = await download(page, limit: 256 * 1024, allowPrefix: true),
      let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
      fallbackPage = responseURL
      candidates = Array(iconURLs(in: html, relativeTo: responseURL).prefix(4))
    }
    if let fallback = URL(string: "/favicon.ico", relativeTo: fallbackPage)?.absoluteURL {
      candidates.append(fallback)
    }
    for candidate in candidates {
      guard !Task.isCancelled else { return nil }
      guard let (data, _) = await download(candidate, limit: 512 * 1024),
        let source = NSImage(data: data), source.isValid else { continue }
      // Keep only a small bitmap, rather than a potentially large source image.
      let image = NSImage(size: NSSize(width: 32, height: 32))
      image.lockFocus()
      source.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
      image.unlockFocus()
      cache.setObject(image, forKey: page as NSURL, cost: 32 * 32 * 4)
      return image
    }
    return nil
  }

  private func download(_ url: URL, limit: Int, allowPrefix: Bool = false) async -> (Data, URL)? {
    guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
    do {
      let (bytes, response) = try await session.bytes(from: url)
      defer { bytes.task.cancel() }
      guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode)
      else { return nil }
      var data = Data()
      for try await byte in bytes {
        try Task.checkCancellation()
        if data.count == limit {
          return allowPrefix ? (data, response.url ?? url) : nil
        }
        data.append(byte)
      }
      return (data, response.url ?? url)
    } catch { return nil }
  }

  private func iconURLs(in html: String, relativeTo page: URL) -> [URL] {
    guard let links = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: .caseInsensitive),
      let attributes = try? NSRegularExpression(
        pattern: #"([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#)
    else { return [] }
    let source = html as NSString
    var urls: [URL] = []
    for match in links.matches(in: html, range: NSRange(location: 0, length: source.length)) {
      let tag = source.substring(with: match.range) as NSString
      var values: [String: String] = [:]
      for attribute in attributes.matches(in: tag as String, range: NSRange(location: 0, length: tag.length)) {
        let key = tag.substring(with: attribute.range(at: 1)).lowercased()
        if let range = (2...4).map({ attribute.range(at: $0) }).first(where: { $0.location != NSNotFound }) {
          values[key] = tag.substring(with: range)
        }
      }
      let relations = (values["rel"] ?? "").lowercased().split(whereSeparator: { $0.isWhitespace })
      guard relations.contains("icon") || relations.contains("apple-touch-icon"),
        let href = values["href"],
        let url = URL(string: href.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: page)?.absoluteURL,
        !urls.contains(url) else { continue }
      urls.append(url)
    }
    return urls
  }
}
