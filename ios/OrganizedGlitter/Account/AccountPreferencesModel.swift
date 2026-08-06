import Foundation
import Observation

struct VerticalPreferences: Codable, Equatable, Sendable {
  var diamondPainting: Bool
  var coloringBooks: Bool

  static let defaultValue = Self(diamondPainting: true, coloringBooks: false)

  var hasEnabledVertical: Bool {
    diamondPainting || coloringBooks
  }

  enum CodingKeys: String, CodingKey {
    case diamondPainting = "diamond_painting"
    case coloringBooks = "coloring_books"
  }
}

struct DashboardSettingsRecord: Decodable, Sendable {
  let id: String
  let verticalEnabled: VerticalPreferences?

  enum CodingKeys: String, CodingKey {
    case id
    case verticalEnabled = "vertical_enabled"
  }
}

@MainActor
@Observable
final class AccountPreferencesModel {
  private let client: PocketBaseClient
  private let userID: String
  private let onUserRefresh: (UserRecord) -> Void

  private(set) var user: UserRecord
  private(set) var verticals = VerticalPreferences.defaultValue
  private(set) var settingsID: String?
  private(set) var isLoading = false
  private(set) var isSaving = false
  var errorMessage: String?

  init(
    client: PocketBaseClient,
    user: UserRecord,
    onUserRefresh: @escaping (UserRecord) -> Void = { _ in }
  ) {
    self.client = client
    userID = user.id
    self.user = user
    self.onUserRefresh = onUserRefresh
  }

  func load() async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    do {
      async let refreshedUser: UserRecord = client.get(collection: "users", id: userID)
      async let loadedSettings = loadSettings()
      let (user, settings) = try await (refreshedUser, loadedSettings)
      apply(user)
      apply(settings)
    } catch APIError.cancelled {
      return
    } catch {
      errorMessage = error.accountMessage
    }
  }

  func updateProfile(username: String) async -> Bool {
    let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      errorMessage = "Enter a profile name."
      return false
    }
    return await updateUser(ProfileUpdate(username: trimmed))
  }

  func updateTheme(_ theme: ThemeFlavor) async -> Bool {
    await updateUser(ThemeUpdate(themePreference: theme.rawValue))
  }

  func updateTimezone(_ identifier: String) async -> Bool {
    guard TimeZone(identifier: identifier) != nil else {
      errorMessage = "Choose a valid time zone."
      return false
    }
    return await updateUser(TimezoneUpdate(timezone: identifier))
  }

  func updateVerticals(_ next: VerticalPreferences) async -> Bool {
    guard next.hasEnabledVertical else {
      errorMessage = "Keep at least one craft enabled."
      return false
    }
    guard !isSaving else {
      return false
    }

    isSaving = true
    errorMessage = nil
    defer { isSaving = false }

    do {
      if let settingsID {
        let record: DashboardSettingsRecord = try await client.update(
          collection: "user_dashboard_settings",
          id: settingsID,
          body: VerticalUpdate(verticalEnabled: next)
        )
        apply(record)
      } else {
        let record: DashboardSettingsRecord = try await client.create(
          collection: "user_dashboard_settings",
          body: NewVerticalSettings(user: userID, verticalEnabled: next)
        )
        apply(record)
      }
      await refreshSettingsAfterWrite()
      return true
    } catch APIError.cancelled {
      return false
    } catch {
      errorMessage = error.accountMessage
      return false
    }
  }

  private func updateUser<Body: Encodable & Sendable>(_ body: Body) async -> Bool {
    guard !isSaving else {
      return false
    }
    isSaving = true
    errorMessage = nil
    defer { isSaving = false }

    do {
      let updated: UserRecord = try await client.update(
        collection: "users", id: userID, body: body)
      apply(updated)
      await refreshUserAfterWrite()
      return true
    } catch APIError.cancelled {
      return false
    } catch {
      errorMessage = error.accountMessage
      return false
    }
  }

  private func loadSettings() async throws -> DashboardSettingsRecord? {
    let result: RecordList<DashboardSettingsRecord> = try await client.list(
      collection: "user_dashboard_settings",
      perPage: 1,
      filter: PocketBaseFilter.equals(.user, userID)
    )
    return result.items.first
  }

  private func refreshUserAfterWrite() async {
    do {
      let refreshed: UserRecord = try await client.get(collection: "users", id: userID)
      apply(refreshed)
    } catch APIError.cancelled {
      return
    } catch {
      errorMessage = "Saved, but the latest account details could not be reloaded."
    }
  }

  private func refreshSettingsAfterWrite() async {
    do {
      apply(try await loadSettings())
    } catch APIError.cancelled {
      return
    } catch {
      errorMessage = "Saved, but the latest craft preferences could not be reloaded."
    }
  }

  private func apply(_ user: UserRecord) {
    self.user = user
    onUserRefresh(user)
  }

  private func apply(_ settings: DashboardSettingsRecord?) {
    settingsID = settings?.id
    verticals = settings?.verticalEnabled.flatMap(VerticalPreferences.validated)
      ?? .defaultValue
  }
}

private extension VerticalPreferences {
  static func validated(_ value: Self) -> Self? {
    value.hasEnabledVertical ? value : nil
  }
}

private struct ProfileUpdate: Encodable, Sendable {
  let username: String
}

private struct ThemeUpdate: Encodable, Sendable {
  let themePreference: String

  enum CodingKeys: String, CodingKey {
    case themePreference = "theme_preference"
  }
}

private struct TimezoneUpdate: Encodable, Sendable {
  let timezone: String
}

private struct VerticalUpdate: Encodable, Sendable {
  let verticalEnabled: VerticalPreferences

  enum CodingKeys: String, CodingKey {
    case verticalEnabled = "vertical_enabled"
  }
}

private struct NewVerticalSettings: Encodable, Sendable {
  let user: String
  let verticalEnabled: VerticalPreferences

  enum CodingKeys: String, CodingKey {
    case user
    case verticalEnabled = "vertical_enabled"
  }
}

private extension Error {
  var accountMessage: String {
    guard let error = self as? APIError else {
      return "The account could not be updated. Try again."
    }
    switch error {
    case .offline:
      return "You appear to be offline. Reconnect and try again."
    case .forbidden:
      return "This account does not have permission to make that change."
    case .validation(let message):
      return message
    case .unauthenticated:
      return "Sign in again to update your account."
    case .emailUnverified, .notFound, .server, .decoding, .cancelled:
      return "The account could not be updated. Try again."
    }
  }
}
