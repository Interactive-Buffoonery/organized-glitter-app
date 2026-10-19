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
  let themePalette: String?
  let analyticsOptOut: Bool?
  let created: String?
  let updated: String?

  enum CodingKeys: String, CodingKey {
    case id, email, verified, username, name, avatar, timezone, created, updated
    case themePreference = "theme_preference"
    case themePalette = "theme_palette"
    case analyticsOptOut = "analytics_opt_out"
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
    themePalette: nil,
    analyticsOptOut: false,
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

enum JWTExpiration {
  static func date(for token: String) -> Date? {
    let parts = token.split(separator: ".")
    guard parts.count == 3 else { return nil }
    var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
    guard let data = Data(base64Encoded: payload),
      let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let expiration = claims["exp"] as? TimeInterval
    else { return nil }
    return Date(timeIntervalSince1970: expiration)
  }
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
