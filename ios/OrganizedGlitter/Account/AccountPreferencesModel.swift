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
  private static let analyticsRefreshError = "Analytics will stay off until your account reloads."
  private static let analyticsConfirmationError =
    "The analytics choice could not be confirmed. Analytics will stay off until your account reloads."
  private let analytics: NativeAnalytics?
  private let client: PocketBaseClient
  private let userID: String
  private let onUserRefresh: (UserRecord) -> Void
  private let onAnalyticsConsentUnknown: () -> Void
  private let onAnalyticsLocalPauseChanged: (Bool) -> Void
  private var userRequestGeneration = 0
  private var analyticsPauseGeneration = 0

  private(set) var user: UserRecord
  private(set) var verticals = VerticalPreferences.defaultValue
  private(set) var settingsID: String?
  private(set) var isAnalyticsLocallyPaused = false
  private(set) var isLoading = false
  private(set) var isRefreshingAnalytics = false
  private(set) var isSaving = false
  var errorMessage: String?

  var isBusy: Bool {
    isLoading || isSaving || isRefreshingAnalytics
  }

  init(
    client: PocketBaseClient,
    user: UserRecord,
    onUserRefresh: @escaping (UserRecord) -> Void = { _ in },
    onAnalyticsConsentUnknown: @escaping () -> Void = {},
    onAnalyticsLocalPauseChanged: @escaping (Bool) -> Void = { _ in },
    analytics: NativeAnalytics? = nil
  ) {
    self.analytics = analytics
    self.client = client
    userID = user.id
    self.user = user
    self.onUserRefresh = onUserRefresh
    self.onAnalyticsConsentUnknown = onAnalyticsConsentUnknown
    self.onAnalyticsLocalPauseChanged = onAnalyticsLocalPauseChanged
  }

  func load() async {
    guard !isLoading, !isSaving, !isRefreshingAnalytics else { return }
    onAnalyticsConsentUnknown()
    let generation = nextUserRequestGeneration()
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    do {
      let user: UserRecord = try await client.get(collection: "users", id: userID)
      guard generation == userRequestGeneration else { return }
      apply(user)
    } catch APIError.cancelled {
      return
    } catch {
      errorMessage = error.accountMessage
      return
    }

    do {
      apply(try await loadSettings())
    } catch APIError.cancelled {
      return
    } catch {
      errorMessage = error.accountMessage
    }
  }

  func pauseAnalyticsLocally() {
    analyticsPauseGeneration &+= 1
    isAnalyticsLocallyPaused = true
    onAnalyticsLocalPauseChanged(true)
  }

  func pollAnalyticsPreference(
    while shouldContinue: () -> Bool,
    wait: () async throws -> Void = { try await Task.sleep(for: .seconds(30)) }
  ) async {
    while !Task.isCancelled, shouldContinue() {
      do { try await wait() } catch { return }
      guard !Task.isCancelled, shouldContinue() else { return }
      await refreshAnalyticsPreference()
    }
  }

  func refreshAnalyticsPreference() async {
    guard !isLoading, !isSaving, !isRefreshingAnalytics else { return }
    let generation = nextUserRequestGeneration()
    isRefreshingAnalytics = true
    defer { isRefreshingAnalytics = false }

    do {
      let refreshed: UserRecord = try await client.get(collection: "users", id: userID)
      guard generation == userRequestGeneration else { return }
      apply(refreshed)
      if errorMessage == Self.analyticsRefreshError
        || errorMessage == Self.analyticsConfirmationError {
        errorMessage = nil
      }
    } catch APIError.cancelled {
      onAnalyticsConsentUnknown()
      return
    } catch {
      onAnalyticsConsentUnknown()
      errorMessage = Self.analyticsRefreshError
    }
  }

  func updateProfile(username: String) async -> Bool {
    let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      errorMessage = "Enter a profile name."
      return false
    }
    return await updateUser(ProfileUpdate(username: trimmed), setting: "profile")
  }

  func updateTheme(_ theme: ThemeFlavor) async -> Bool {
    await updateUser(ThemeUpdate(themePreference: theme.rawValue), setting: "theme")
  }

  func updatePalette(_ palette: ThemePalette) async -> Bool {
    await updateUser(PaletteUpdate(themePalette: palette.rawValue), setting: "palette")
  }

  func updateTimezone(_ identifier: String) async -> Bool {
    guard TimeZone(identifier: identifier) != nil else {
      errorMessage = "Choose a valid time zone."
      return false
    }
    return await updateUser(TimezoneUpdate(timezone: identifier), setting: "timezone")
  }

  func updateAnalyticsEnabled(_ enabled: Bool) async -> Bool {
    guard !isSaving, !isLoading, !isRefreshingAnalytics else {
      return false
    }
    onAnalyticsConsentUnknown()
    let generation = nextUserRequestGeneration()
    let expectedOptOut = !enabled
    let pauseGeneration = analyticsPauseGeneration
    isSaving = true
    errorMessage = nil
    defer { isSaving = false }

    do {
      let updated: UserRecord = try await client.update(
        collection: "users", id: userID,
        body: AnalyticsUpdate(analyticsOptOut: expectedOptOut))
      guard generation == userRequestGeneration else { return false }
      guard updated.analyticsOptOut == expectedOptOut else {
        return await reconcileAnalyticsPreference(
          expectedOptOut: expectedOptOut, generation: generation, pauseGeneration: pauseGeneration)
      }
      confirmAnalyticsSave(pauseGeneration: pauseGeneration)
      apply(updated)
      await refreshUserAfterWrite(generation: generation)
      return true
    } catch APIError.cancelled {
      return false
    } catch {
      return await reconcileAnalyticsPreference(
        expectedOptOut: expectedOptOut, generation: generation, pauseGeneration: pauseGeneration)
    }
  }

  func updateVerticals(_ next: VerticalPreferences) async -> Bool {
    guard next.hasEnabledVertical else {
      errorMessage = "Keep at least one craft enabled."
      return false
    }
    guard !isSaving, !isLoading, !isRefreshingAnalytics else {
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
      analytics?.capture(.verticalsUpdated, properties: [
        "diamond_painting": verticals.diamondPainting, "coloring_books": verticals.coloringBooks,
      ], accountID: userID)
      await refreshSettingsAfterWrite()
      return true
    } catch APIError.cancelled {
      return false
    } catch {
      errorMessage = error.accountMessage
      return false
    }
  }

  private func updateUser<Body: Encodable & Sendable>(_ body: Body, setting: String) async -> Bool {
    guard !isSaving, !isLoading, !isRefreshingAnalytics else {
      return false
    }
    let generation = nextUserRequestGeneration()
    isSaving = true
    errorMessage = nil
    defer { isSaving = false }

    do {
      let updated: UserRecord = try await client.update(
        collection: "users", id: userID, body: body)
      guard generation == userRequestGeneration else { return false }
      apply(updated)
      analytics?.capture(.accountUpdated, properties: ["setting": setting], accountID: userID)
      await refreshUserAfterWrite(generation: generation)
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

  private func refreshUserAfterWrite(generation: Int) async {
    do {
      let refreshed: UserRecord = try await client.get(collection: "users", id: userID)
      guard generation == userRequestGeneration else { return }
      apply(refreshed)
    } catch APIError.cancelled {
      return
    } catch {
      errorMessage = "Saved, but the latest account details could not be reloaded."
    }
  }

  private func reconcileAnalyticsPreference(
    expectedOptOut: Bool, generation: Int, pauseGeneration: Int
  ) async -> Bool {
    do {
      let refreshed: UserRecord = try await client.get(collection: "users", id: userID)
      guard generation == userRequestGeneration else { return false }
      apply(refreshed)
      guard refreshed.analyticsOptOut == expectedOptOut else {
        errorMessage = "The analytics choice could not be saved. Your current account choice was reloaded."
        return false
      }
      confirmAnalyticsSave(pauseGeneration: pauseGeneration)
      errorMessage = nil
      return true
    } catch {
      errorMessage = Self.analyticsConfirmationError
      return false
    }
  }

  private func confirmAnalyticsSave(pauseGeneration: Int) {
    guard pauseGeneration == analyticsPauseGeneration else { return }
    isAnalyticsLocallyPaused = false
    onAnalyticsLocalPauseChanged(false)
  }

  private func nextUserRequestGeneration() -> Int {
    userRequestGeneration &+= 1
    return userRequestGeneration
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
    if self.user != user { self.user = user }
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

private struct PaletteUpdate: Encodable, Sendable {
  let themePalette: String

  enum CodingKeys: String, CodingKey {
    case themePalette = "theme_palette"
  }
}

private struct TimezoneUpdate: Encodable, Sendable {
  let timezone: String
}

private struct AnalyticsUpdate: Encodable, Sendable {
  let analyticsOptOut: Bool

  enum CodingKeys: String, CodingKey {
    case analyticsOptOut = "analytics_opt_out"
  }
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
      return APIError.needsConnection("Changing account settings")
    case .forbidden:
      return "This account does not have permission to make that change."
    case .validation(let message):
      return message
    case .unauthenticated:
      return "Sign in again to update your account."
    case .emailUnverified, .notFound, .server, .decoding, .cancelled, .conflict:
      return "The account could not be updated. Try again."
    }
  }
}
