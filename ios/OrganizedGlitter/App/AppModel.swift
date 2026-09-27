import Foundation
import OSLog
import Observation

@MainActor
@Observable
final class AppModel {
  enum Phase: Equatable {
    case restoring
    case cleaningLocalData
    case cleanupFailed
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
  private var localStore: LocalLibraryStore?
  private(set) var library: LibrarySession?
  var requiresDiscardConfirmation = false
  private(set) var sessionError: String?
  private(set) var isSigningOut = false
  private var userSaveTask: Task<Void, Never>?
  private var cleanupBlocked = false

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

  init(
    client: PocketBaseClient, sessionStore: KeychainSessionStore, themeStore: ThemeStore,
    localStore: LocalLibraryStore? = nil
  ) {
    self.client = client
    self.sessionStore = sessionStore
    self.themeStore = themeStore
    phase = .restoring
    do {
      self.localStore = try localStore ?? LocalLibraryStore.inMemory()
    } catch {
      phase = .configurationError("The local library could not be opened.")
      return
    }

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
            try await openLibrary(for: session.user, generation: generation)
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
      guard case .restoring = phase else { return }
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
    guard !isSigningOut, let client, let sessionStore, let localStore else { return }
    let generation = beginSessionTransition()
    do { try await finishPendingLocalRemoval() }
    catch {
      guard generation == sessionGeneration else { return }
      cleanupBlocked = true
      phase = .cleanupFailed
      return
    }
    guard generation == sessionGeneration else { return }
    do {
      guard let stored = try sessionStore.load() else {
        await RemoteArtworkLoader.shared.purgeMemoryCache()
        guard generation == sessionGeneration else { return }
        phase = .signedOut
        return
      }
      let scope = LocalAccountScope(backendURL: client.baseURL, userID: stored.userID)
      let cachedUser = try await localStore.loadUser(scope: scope)
      guard generation == sessionGeneration else { return }
      if let user = cachedUser, user.verified == true {
        await client.prepareOfflineSession(stored)
        guard generation == sessionGeneration else { return }
        try await openLibrary(for: user, generation: generation)
        guard generation == sessionGeneration else { return }
        phase = .signedIn(user)
        applyThemePreference(from: user)
      }
      let session = try await client.restore(stored)
      guard generation == sessionGeneration else { return }
      try await openLibrary(for: session.user, generation: generation)
      guard generation == sessionGeneration else { return }
      phase = .signedIn(session.user)
      applyThemePreference(from: session.user)
    } catch APIError.cancelled {
      return
    } catch APIError.offline {
      guard generation == sessionGeneration else { return }
      if library == nil { phase = .offline }
    } catch APIError.unauthenticated, APIError.forbidden {
      guard generation == sessionGeneration else { return }
      await clearInvalidSession(using: sessionStore)
    } catch {
      guard generation == sessionGeneration else { return }
      if library == nil { phase = .restorationFailed }
    }
  }

  private func openLibrary(for user: UserRecord, generation: Int? = nil) async throws {
    let generation = generation ?? sessionGeneration
    guard generation == sessionGeneration else { throw APIError.cancelled }
    guard let client, let localStore else { throw LocalLibraryError.storageUnavailable }
    let scope = LocalAccountScope(backendURL: client.baseURL, userID: user.id)
    try await localStore.saveUser(user, scope: scope)
    guard generation == sessionGeneration else { throw APIError.cancelled }
    if library?.scope == scope { return }
    try await library?.close(removingData: false)
    await RemoteArtworkLoader.shared.purgeMemoryCache()
    guard generation == sessionGeneration else { throw APIError.cancelled }
    let next = LibrarySession(client: client, userID: user.id, store: localStore)
    next.onAuthenticationFailure = { [weak self] in await self?.expireSession() }
    try await next.loadLocal()
    guard generation == sessionGeneration else { throw APIError.cancelled }
    library = next
  }

  private func clearInvalidSession(using sessionStore: KeychainSessionStore) async {
    try? await library?.close(removingData: false)
    library = nil
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
      guard case .restoring = phase else { return }
      await restoreSession()
    }
  }

  func signIn(identity: String, password: String) async {
    guard !isSigningOut, !cleanupBlocked, !isSubmitting, let client else { return }

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
      try await openLibrary(for: session.user, generation: generation)
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
    guard !isSigningOut else { return }
    sessionGeneration &+= 1
    await drainUserSave()
    try? await library?.close(removingData: false)
    library = nil
    await client?.signOut()
    await RemoteArtworkLoader.shared.purgeMemoryCache()
    phase = .signedOut
  }

  func signOut(discardPending: Bool = false) {
    guard !isSigningOut else { return }
    isSigningOut = true
    sessionGeneration &+= 1
    library?.pauseWrites()
    sessionError = nil
    Task {
      defer {
        isSigningOut = false
        library?.resumeWrites()
      }
      do {
        try await library?.loadLocal()
        if !discardPending, let library, library.pendingCount > 0 {
          requiresDiscardConfirmation = true
          return
        }
        sessionGeneration &+= 1
        await drainUserSave()
        if let library { try await localStore?.beginRemoval(scope: library.scope) }
        cleanupBlocked = true
        phase = .cleaningLocalData
        try sessionStore?.clear()
        await client?.signOut()
        try await library?.close(removingData: true)
        library = nil
        await RemoteArtworkLoader.shared.purgeMemoryCache()
        #if DEBUG
          UserDefaults.standard.removeObject(forKey: OverviewFixtureProtocol.sampleDataKey)
        #endif
        requiresDiscardConfirmation = false
        cleanupBlocked = false
        phase = .signedOut
      } catch {
        sessionError = "Sign-out could not finish clearing local data. Please try again."
        if cleanupBlocked {
          try? await library?.close(removingData: false)
          library = nil
          await RemoteArtworkLoader.shared.purgeMemoryCache()
          phase = .cleanupFailed
        }
      }
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

  private func finishPendingLocalRemoval() async throws {
    guard let localStore, let client else { return }
    let scopes = try await localStore.pendingRemovals()
    guard !scopes.isEmpty else { cleanupBlocked = false; return }
    cleanupBlocked = true
    phase = .cleaningLocalData
    await drainUserSave()
    try sessionStore?.clear()
    await client.signOut()
    for scope in scopes {
      try await localStore.removeScope(scope)
      try await client.removeDownloadedArtwork(scope: scope)
      try await localStore.finishRemoval(scope: scope)
    }
    await RemoteArtworkLoader.shared.purgeMemoryCache()
    cleanupBlocked = false
  }

  private func drainUserSave() async {
    userSaveTask?.cancel()
    if let task = userSaveTask { await task.value }
    userSaveTask = nil
  }

  func replaceSignedInUser(_ user: UserRecord) {
    guard !isSigningOut, !cleanupBlocked, case .signedIn(let current) = phase,
      current.id == user.id else { return }
    phase = .signedIn(user)
    applyThemePreference(from: user)
    if let library, let localStore {
      let generation = sessionGeneration
      let previous = userSaveTask
      previous?.cancel()
      userSaveTask = Task { [weak self] in
        if let previous { await previous.value }
        guard let self, !Task.isCancelled, generation == self.sessionGeneration else { return }
        do { try await localStore.saveUser(user, scope: library.scope) }
        catch {
          guard generation == self.sessionGeneration, !Task.isCancelled else { return }
          self.sessionError = "Your account settings could not be saved on this device."
        }
      }
    }
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
