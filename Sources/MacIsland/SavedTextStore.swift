import Foundation

struct SavedItem: Codable, Identifiable {
  let id: UUID
  var text: String
  var title: String?

  var webURL: URL? {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, !value.contains(where: { $0.isWhitespace }) else { return nil }
    let explicitScheme = value.contains("://")
    guard let parts = URLComponents(string: explicitScheme ? value : "https://" + value),
      ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
      let host = parts.host, !host.isEmpty, let url = parts.url else { return nil }
    if !explicitScheme {
      let labels = host.split(separator: ".", omittingEmptySubsequences: false)
      guard parts.user == nil, parts.password == nil, labels.count >= 2,
        labels.allSatisfy({ !$0.isEmpty }),
        let suffix = labels.last, suffix.count >= 2, suffix.allSatisfy({ $0.isLetter })
      else { return nil }
    }
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
