import Foundation
import Security
import Testing

@testable import OrganizedGlitter

struct KeychainSessionStoreTests {
  @Test
  func savesLoadsAndClearsSession() throws {
    let service = "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    let store = KeychainSessionStore(service: service)
    let session = AuthenticatedSession(token: "test-token", user: .preview)

    try store.save(session)
    #expect(try store.load() == StoredSession(token: "test-token", userID: "preview-user"))
    #expect(
      try keychainAccessibility(service: service)
        == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
    )

    try store.save(AuthenticatedSession(token: "refreshed-token", user: .preview))
    #expect(try store.load() == StoredSession(token: "refreshed-token", userID: "preview-user"))
    #expect(
      try keychainAccessibility(service: service)
        == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
    )

    try store.clear()
    #expect(try store.load() == nil)
  }

  @Test
  func saveMigratesLegacyKeychainAccessibility() throws {
    let service = "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    let store = KeychainSessionStore(service: service)
    let legacyData = try JSONEncoder().encode(
      StoredSession(token: "legacy-token", userID: "preview-user")
    )

    let addStatus = SecItemAdd(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: "pocketbase.session",
        kSecValueData as String: legacyData,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      ] as CFDictionary,
      nil
    )
    #expect(addStatus == errSecSuccess)
    #expect(
      try keychainAccessibility(service: service)
        == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
    )

    try store.save(AuthenticatedSession(token: "migrated-token", user: .preview))

    #expect(try store.load() == StoredSession(token: "migrated-token", userID: "preview-user"))
    #expect(
      try keychainAccessibility(service: service)
        == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
    )

    try store.clear()
  }

  private func keychainAccessibility(service: String) throws -> String {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "pocketbase.session",
      kSecReturnAttributes as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess,
      let attributes = item as? [String: Any],
      let accessibility = attributes[kSecAttrAccessible as String] as? String
    else {
      throw KeychainError(status)
    }
    return accessibility
  }
}
