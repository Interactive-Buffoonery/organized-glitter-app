import Foundation
import Security

struct KeychainDeletionIntentStore {
  let service: String
  private var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service,
     kSecAttrAccount as String: "pocketbase.account-deletion"]
  }

  func save(_ intent: AccountDeletionIntent) throws {
    try intent.validate()
    let attributes: [String: Any] = [
      kSecValueData as String: try JSONEncoder().encode(intent),
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if update == errSecSuccess { return }
    guard update == errSecItemNotFound else { throw KeychainError(update) }
    let insert = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
    guard insert == errSecSuccess else { throw KeychainError(insert) }
  }

  func load() throws -> AccountDeletionIntent? {
    var request = query
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status) }
    let intent = try JSONDecoder().decode(AccountDeletionIntent.self, from: data)
    try intent.validate()
    return intent
  }

  func clear() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status) }
  }
}
