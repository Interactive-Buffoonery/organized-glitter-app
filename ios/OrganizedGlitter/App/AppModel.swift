import Foundation
import OSLog
import Observation

@MainActor
@Observable
final class AppModel {
  enum Phase: Equatable {
    case restoring
    case signedOut
    case signedIn(UserRecord)
    case offline
    case restorationFailed
    case configurationError(String)
  }

  private static let logger = Logger(
    subsystem: "com.interactivebuffoonery.organizedglitter",
    category: "Session"
  )

  @ObservationIgnored let client: PocketBaseClient?
  private let sessionStore: KeychainSessionStore?
  private let themeStore: ThemeStore?
  @ObservationIgnored private var sessionGeneration = 0

  var phase: Phase {
    didSet {
      routePendingPasswordReset()
    }
  }
  var signInError: String?
  var isSubmitting = false
  var passwordResetDestination: PasswordResetDestination?
  var showsSignedInPasswordResetNotice = false
  private var pendingPasswordResetLink: PasswordResetLink?

  init(client: PocketBaseClient, sessionStore: KeychainSessionStore, themeStore: ThemeStore) {
    self.client = client
    self.sessionStore = sessionStore
    self.themeStore = themeStore
    phase = .restoring

    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-restoring") {
        return
      }
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-signed-out") {
        phase = .signedOut
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-password-reset") {
          open(URL(string: "https://organizedglitter.app/auth/confirm-password-reset/fixture-token")!)
        }
        return
      }
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-authenticated")
        || UserDefaults.standard.bool(forKey: OverviewFixtureProtocol.sampleDataKey)
      {
        let generation = beginSessionTransition()
        Task {
          do {
            let session = try await client.signIn(identity: "fixture", password: "fixture")
            guard generation == sessionGeneration else { return }
            phase = .signedIn(session.user)
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-password-reset") {
              open(
                URL(
                  string: "https://organizedglitter.app/auth/confirm-password-reset/fixture-token"
                )!
              )
            }
          } catch {
            guard generation == sessionGeneration else { return }
            phase = .restorationFailed
          }
        }
        return
      }
    #endif

    Task {
      await restoreSession()
    }
  }

  init(configurationError: Error, themeStore: ThemeStore) {
    client = nil
    sessionStore = nil
    self.themeStore = themeStore
    phase = .configurationError(configurationError.localizedDescription)
  }

  func restoreSession() async {
    guard let client, let sessionStore else {
      return
    }
    let generation = beginSessionTransition()

    do {
      guard let storedSession = try sessionStore.load() else {
        await RemoteArtworkLoader.shared.purgeMemoryCache()
        guard generation == sessionGeneration else { return }
        phase = .signedOut
        return
      }

      let session = try await client.restore(storedSession)
      guard generation == sessionGeneration else { return }
      phase = .signedIn(session.user)
      applyThemePreference(from: session.user)
    } catch APIError.cancelled {
      return
    } catch APIError.offline {
      guard generation == sessionGeneration else { return }
      phase = .offline
    } catch APIError.unauthenticated, APIError.forbidden {
      guard generation == sessionGeneration else { return }
      await clearInvalidSession(using: sessionStore)
    } catch {
      guard generation == sessionGeneration else { return }
      phase = .restorationFailed
    }
  }

  private func clearInvalidSession(using sessionStore: KeychainSessionStore) async {
    do {
      try sessionStore.clear()
    } catch {
      Self.logger.error("Unable to clear an invalid local session.")
    }
    await RemoteArtworkLoader.shared.purgeMemoryCache()
    phase = .signedOut
  }

  func retrySessionRestoration() {
    phase = .restoring
    Task {
      await restoreSession()
    }
  }

  func signIn(identity: String, password: String) async {
    guard let client else {
      return
    }

    let trimmedIdentity = identity.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedIdentity.isEmpty, !password.isEmpty else {
      signInError = "Enter your email address and password."
      return
    }
    let generation = beginSessionTransition()

    isSubmitting = true
    signInError = nil
    defer {
      if generation == sessionGeneration {
        isSubmitting = false
      }
    }

    do {
      let session = try await client.signIn(identity: trimmedIdentity, password: password)
      guard generation == sessionGeneration else { return }
      phase = .signedIn(session.user)
      applyThemePreference(from: session.user)
    } catch APIError.cancelled {
      return
    } catch {
      guard generation == sessionGeneration else { return }
      signInError = error.userFacingMessage
    }
  }

  func expireSession() async {
    guard let client else {
      return
    }
    await client.signOut()
    await RemoteArtworkLoader.shared.purgeMemoryCache()
    phase = .signedOut
  }

  func signOut() {
    #if DEBUG
      UserDefaults.standard.removeObject(forKey: OverviewFixtureProtocol.sampleDataKey)
    #endif
    guard let client else {
      return
    }
    let generation = beginSessionTransition()
    isSubmitting = false
    signInError = nil

    Task {
      await client.signOut()
      await RemoteArtworkLoader.shared.purgeMemoryCache()
      guard generation == sessionGeneration else { return }
      phase = .signedOut
    }
  }

  func open(_ url: URL) {
    guard let link = PasswordResetLink.parse(url) else {
      return
    }
    pendingPasswordResetLink = link
    routePendingPasswordReset()
  }

  private func routePendingPasswordReset() {
    guard phase != .restoring else { return }
    if case .signedIn = phase {
      guard pendingPasswordResetLink != nil || passwordResetDestination != nil else { return }
      pendingPasswordResetLink = nil
      passwordResetDestination = nil
      showsSignedInPasswordResetNotice = true
      return
    }
    guard let link = pendingPasswordResetLink else { return }
    pendingPasswordResetLink = nil
    passwordResetDestination = PasswordResetDestination(link: link)
  }

  func passwordResetConfirmed() async {
    guard let client else {
      return
    }
    let generation = beginSessionTransition()
    isSubmitting = false
    signInError = nil
    await client.signOut()
    guard generation == sessionGeneration else { return }
    phase = .signedOut
  }

  func replaceSignedInUser(_ user: UserRecord) {
    guard case .signedIn = phase else {
      return
    }
    phase = .signedIn(user)
    applyThemePreference(from: user)
  }

  /// Seeds the device-local theme from the signed-in account's preference. The
  /// web application stores `theme_preference` on the user record; only
  /// system/light/dark carry over — the web's Catppuccin flavor names don't
  /// exist on iOS and are deliberately ignored, keeping the device preference.
  /// AccountPreferencesModel writes supported theme choices back to the account.
  private func applyThemePreference(from user: UserRecord) {
    guard let themeStore, let preference = user.themePreference else {
      return
    }
    if let flavor = ThemeFlavor(rawValue: preference) {
      themeStore.flavor = flavor
    }
  }

  private func beginSessionTransition() -> Int {
    sessionGeneration &+= 1
    return sessionGeneration
  }
}

extension Error {
  fileprivate var userFacingMessage: String {
    guard let apiError = self as? APIError else {
      return "Organized Glitter could not sign you in. Try again."
    }

    switch apiError {
    case .unauthenticated:
      return "That email address and password do not match."
    case .emailUnverified:
      return
        "Verify your email address before signing in. You can request a new verification email below."
    case .forbidden:
      return "This account does not have permission to sign in."
    case .validation(let message):
      return message
    case .offline:
      return "You appear to be offline. Reconnect and try again."
    case .notFound:
      return "That account could not be found."
    case .server, .decoding, .cancelled:
      return "Organized Glitter is unavailable right now. Try again shortly."
    }
  }
}
