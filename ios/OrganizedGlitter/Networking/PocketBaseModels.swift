import Foundation

struct UserRecord: Codable, Equatable, Sendable {
  let id: String
  let email: String?
  let verified: Bool?
  let username: String?
  let name: String?
  let avatar: String?
  let timezone: String?
  let themePreference: String?
  let created: String?
  let updated: String?

  enum CodingKeys: String, CodingKey {
    case id, email, verified, username, name, avatar, timezone, created, updated
    case themePreference = "theme_preference"
  }

  static let preview = UserRecord(
    id: "preview-user",
    email: "sarah@example.test",
    verified: true,
    username: "Sarah",
    name: "Sarah",
    avatar: nil,
    timezone: nil,
    themePreference: nil,
    created: nil,
    updated: nil
  )
}

struct AuthenticatedSession: Codable, Equatable, Sendable {
  let token: String
  let user: UserRecord
}

struct StoredSession: Codable, Equatable, Sendable {
  let token: String
  let userID: String
}

struct AuthResponse: Decodable, Sendable {
  let token: String
  let record: UserRecord

  var session: AuthenticatedSession {
    AuthenticatedSession(token: token, user: record)
  }
}

struct RecordList<Record: Decodable & Sendable>: Decodable, Sendable {
  let page: Int
  let perPage: Int
  let totalItems: Int
  let totalPages: Int
  let items: [Record]
}
