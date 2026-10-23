import Foundation

struct SavedItem: Codable, Identifiable {
  let id: UUID
  let text: String
  var title: String?

  var webURL: URL? {
    guard !text.contains(where: { $0.isWhitespace }),
      let parts = URLComponents(string: text),
      ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
      let host = parts.host, !host.isEmpty, let url = parts.url
    else { return nil }
    return url
  }
}

struct SavedTextStore {
  private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Mac Island/Saved Text.json")

  func load() throws -> [SavedItem] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    return try JSONDecoder().decode([SavedItem].self, from: Data(contentsOf: url))
  }

  func save(_ items: [SavedItem]) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(items).write(to: url, options: .atomic)
  }
}
