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

  var phase: Phase
  var signInError: String?
  var isSubmitting = false

  init(client: PocketBaseClient, sessionStore: KeychainSessionStore, themeStore: ThemeStore) {
    self.client = client
    self.sessionStore = sessionStore
    self.themeStore = themeStore
    phase = .restoring

    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-signed-out") {
        phase = .signedOut
        return
      }
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-authenticated") {
        phase = .signedIn(.preview)
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

    do {
      guard let storedSession = try sessionStore.load() else {
        phase = .signedOut
        return
      }

      let session = try await client.restore(storedSession)
      phase = .signedIn(session.user)
      applyThemePreference(from: session.user)
    } catch APIError.offline {
      phase = .offline
    } catch APIError.unauthenticated, APIError.forbidden {
      clearInvalidSession(using: sessionStore)
    } catch {
      phase = .restorationFailed
    }
  }

  private func clearInvalidSession(using sessionStore: KeychainSessionStore) {
    do {
      try sessionStore.clear()
    } catch {
      Self.logger.error("Unable to clear an invalid local session.")
    }
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

    isSubmitting = true
    signInError = nil
    defer { isSubmitting = false }

    do {
      let session = try await client.signIn(identity: trimmedIdentity, password: password)
      phase = .signedIn(session.user)
      applyThemePreference(from: session.user)
    } catch {
      signInError = error.userFacingMessage
    }
  }

  func signOut() {
    guard let client else {
      return
    }

    Task {
      await client.signOut()
      phase = .signedOut
    }
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
      return "Verify your email address before signing in. You can request a new verification email below."
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
