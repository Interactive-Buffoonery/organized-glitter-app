import Foundation
import Security

struct KeychainSessionStore: Sendable {
  private static let accessibility = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String

  private let service: String
  private let account = "pocketbase.session"

  init(service: String = "com.interactivebuffoonery.organizedglitter") {
    self.service = service
  }

  func save(_ session: AuthenticatedSession) throws {
    let stored = StoredSession(token: session.token, userID: session.user.id)
    let data = try JSONEncoder().encode(stored)
    let query = baseQuery

    let updateStatus = SecItemUpdate(
      query as CFDictionary,
      [
        kSecValueData as String: data,
        kSecAttrAccessible as String: Self.accessibility,
      ] as CFDictionary
    )
    if updateStatus == errSecSuccess {
      return
    }
    guard updateStatus == errSecItemNotFound else {
      throw KeychainError(updateStatus)
    }

    var attributes = query
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = Self.accessibility

    let status = SecItemAdd(attributes as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw KeychainError(status)
    }
  }

  func load() throws -> StoredSession? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)

    if status == errSecItemNotFound {
      return nil
    }

    guard status == errSecSuccess, let data = item as? Data else {
      throw KeychainError(status)
    }

    return try JSONDecoder().decode(StoredSession.self, from: data)
  }

  func clear() throws {
    let status = SecItemDelete(baseQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError(status)
    }
  }

  private var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}

struct KeychainError: Error {
  let status: OSStatus

  init(_ status: OSStatus) {
    self.status = status
  }
}
