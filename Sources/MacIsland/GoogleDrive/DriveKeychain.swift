import Foundation
import Security

enum DriveKeychain {
  static func read<T: Decodable>(_ key: String, as type: T.Type) throws -> T? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "local.macisland.google-drive", kSecAttrAccount as String: key,
      kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw DriveFailure.message("Cannot read Google Drive credentials from Keychain.")
    }
    return try JSONDecoder().decode(type, from: data)
  }

  static func write<T: Encodable>(_ value: T, key: String) throws {
    let data = try JSONEncoder().encode(value)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "local.macisland.google-drive", kSecAttrAccount as String: key,
    ]
    let status = SecItemUpdate(
      query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var insertion = query
      insertion[kSecValueData as String] = data
      insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else {
        throw DriveFailure.message("Cannot save Google Drive credentials in Keychain.")
      }
    } else if status != errSecSuccess {
      throw DriveFailure.message("Cannot update Google Drive credentials in Keychain.")
    }
  }
}

enum DriveFailure: LocalizedError {
  case message(String)
  var errorDescription: String? {
    if case .message(let text) = self { return text }
    return nil
  }
}

struct GoogleClientConfiguration: Codable {
  let clientID: String
  let clientSecret: String
}

struct GoogleTokens: Codable {
  var accessToken: String
  var refreshToken: String
  var expires: Date
}
