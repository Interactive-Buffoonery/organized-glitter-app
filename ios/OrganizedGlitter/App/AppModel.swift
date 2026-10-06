import Foundation
import AuthenticationServices
import OSLog
import Observation

@MainActor
@Observable
final class AppModel {
  enum AppleReadiness: Equatable {
    case loading
    case available
    case unavailable
    case failed
  }

  private struct AppleAttempt {
    let generation: Int
    let sourceID: UUID
    let state: String
    let nonce: AppleSignInNonce
  }

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
  let analytics: NativeAnalytics
  private var hasCapturedAppOpen = false
  private let sessionStore: KeychainSessionStore?
  private let themeStore: ThemeStore?
  @ObservationIgnored private var sessionGeneration = 0
  private var localStore: LocalLibraryStore?
  private(set) var library: LibrarySession?
  var requiresDiscardConfirmation = false
  private(set) var sessionError: String?
  private(set) var isSigningOut = false {
    didSet { updateAnalyticsSession() }
  }
  private var userSaveTask: Task<Void, Never>?
  private var cleanupBlocked = false
  @ObservationIgnored private var oauthAttemptID: UUID?
  @ObservationIgnored private var oauthTask: Task<Void, Never>?
  @ObservationIgnored private var oauthTimeoutTask: Task<Void, Never>?
  @ObservationIgnored private var oauthBrowser: OAuthWebSession?
  @ObservationIgnored private var appleTimeoutTask: Task<Void, Never>?
  @ObservationIgnored private var appleTask: Task<Void, Never>?
  @ObservationIgnored private var appleAttempt: AppleAttempt?
  @ObservationIgnored private var appleReadinessGeneration = 0

  var phase: Phase {
    didSet {
      updateAnalyticsSession()
      routePendingPasswordReset()
    }
  }
  var signInError: String?
  var oauthError: String?
  var appleError: String?
  var appleReadiness: AppleReadiness = .loading
  var socialProviders: [SocialProvider] = []
  var isSubmitting = false
  var passwordResetDestination: PasswordResetDestination?
  var showsSignedInPasswordResetNotice = false
  private var pendingPasswordResetLink: PasswordResetLink?

  init(
    client: PocketBaseClient, sessionStore: KeychainSessionStore, themeStore: ThemeStore,
    localStore: LocalLibraryStore? = nil, analytics: NativeAnalytics? = nil
  ) {
    self.client = client
    self.sessionStore = sessionStore
    self.themeStore = themeStore
    self.analytics = analytics ?? NativeAnalytics()
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
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-authenticated") {
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
    analytics = NativeAnalytics()
    sessionStore = nil
    self.themeStore = themeStore
    phase = .configurationError(configurationError.localizedDescription)
  }

  private func updateAnalyticsSession() {
    switch phase {
    case .signedIn(let user) where !isSigningOut:
      analytics.setSession(accountID: user.id, isActive: true)
    case .signedOut where !isSigningOut:
      analytics.setSession(accountID: nil, isActive: true)
    default:
      analytics.setSession(accountID: nil, isActive: false)
    }
    guard !hasCapturedAppOpen, !isSigningOut else { return }
    switch phase {
    case .signedOut, .signedIn:
      hasCapturedAppOpen = true
      analytics.capture(.appOpened)
    default:
      break
    }
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

  func loadSocialProviders() async {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-signed-out") {
        socialProviders = ProcessInfo.processInfo.arguments.contains("-ui-testing-social-providers")
          ? [.google, .discord] : []
        return
      }
    #endif
    guard let client else { return }
    do {
      let providers = try await client.oauthProviders()
      guard case .signedOut = phase else { return }
      socialProviders = providers.compactMap { SocialProvider(rawValue: $0.name) }
    } catch {
      socialProviders = []
    }
  }

  func loadAppleReadiness() async {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-ui-testing-signed-out") {
        appleReadiness = ProcessInfo.processInfo.arguments.contains("-ui-testing-apple-available")
          ? .available : .unavailable
        return
      }
    #endif
    guard let client else {
      appleReadiness = .unavailable
      return
    }
    appleReadinessGeneration &+= 1
    let generation = appleReadinessGeneration
    appleReadiness = .loading
    do {
      let available = try await client.appleNativeReadiness()
      guard generation == appleReadinessGeneration else { return }
      appleReadiness = available ? .available : .unavailable
    } catch {
      guard generation == appleReadinessGeneration else { return }
      appleReadiness = .failed
    }
  }

  func loadSignInMethods() async {
    async let apple: Void = loadAppleReadiness()
    async let social: Void = loadSocialProviders()
    _ = await (apple, social)
  }

  func configureAppleRequest(
    _ request: ASAuthorizationAppleIDRequest, sourceID: UUID,
    timeout: Duration = .seconds(120)
  ) {
    guard appleReadiness == .available, case .signedOut = phase,
      !isSigningOut, !cleanupBlocked, !isSubmitting, appleAttempt == nil, appleTask == nil
    else { return }
    let generation = beginSessionTransition()
    appleError = nil
    do {
      let nonce = try AppleSignInNonce.generate()
      let state = UUID().uuidString
      appleAttempt = AppleAttempt(
        generation: generation,
        sourceID: sourceID,
        state: state,
        nonce: nonce
      )
      request.requestedScopes = [.fullName, .email]
      request.nonce = nonce.digest
      request.state = state
      isSubmitting = true
      appleTimeoutTask = Task { [weak self] in
        try? await Task.sleep(for: timeout)
        guard !Task.isCancelled, let self, generation == self.sessionGeneration else { return }
        self.cancelAppleSignIn()
        self.appleError = "Apple sign-in timed out. Try again."
      }
    } catch {
      appleError = "Apple sign-in could not start securely. Try again."
      isSubmitting = false
    }
  }

  func completeAppleAuthorization(_ outcome: AppleAuthorizationOutcome, sourceID: UUID) {
    guard let attempt = appleAttempt,
      attempt.generation == sessionGeneration,
      attempt.sourceID == sourceID
    else { return }
    switch outcome {
    case .cancelled:
      finishAppleSignIn()
    case .failed:
      finishAppleSignIn()
      appleError = "Apple sign-in could not finish. Try again."
    case .invalidCredential:
      finishAppleSignIn()
      appleError = "Apple did not provide a valid authorization. Try again."
    case .authorized(let state, let code, let name):
      guard state == attempt.state else {
        finishAppleSignIn()
        appleError = "Apple did not provide a valid authorization. Try again."
        return
      }
      guard let code, !code.isEmpty, let client else {
        finishAppleSignIn()
        appleError = "Apple did not provide a valid authorization. Try again."
        return
      }
      appleTask = Task {
        defer {
          if attempt.generation == sessionGeneration {
            finishAppleSignIn()
          }
        }
        do {
          let session = try await client.signInWithApple(
            code: code,
            nonce: attempt.nonce.raw,
            name: name
          )
          guard attempt.generation == sessionGeneration else { return }
          try await openLibrary(for: session.user, generation: attempt.generation)
          guard attempt.generation == sessionGeneration else { return }
          phase = .signedIn(session.user)
          applyThemePreference(from: session.user)
        } catch is CancellationError {
          return
        } catch APIError.cancelled {
          return
        } catch {
          guard attempt.generation == sessionGeneration else { return }
          appleError = Self.appleMessage(for: error)
        }
      }
    }
  }

  private func finishAppleSignIn() {
    appleTimeoutTask?.cancel()
    appleTimeoutTask = nil
    appleTask = nil
    appleAttempt = nil
    isSubmitting = false
  }

  func cancelAppleSignIn() {
    guard appleAttempt != nil || appleTask != nil else { return }
    _ = beginSessionTransition()
    isSubmitting = false
  }

  private static func appleMessage(for error: Error) -> String {
    switch error {
    case AppleSignInError.invalidCredential, AppleSignInError.invalidAuthorization:
      return "Apple did not complete sign-in. Start a new Apple sign-in and try again."
    case AppleSignInError.rateLimited:
      return "Too many Apple sign-in attempts. Wait a moment and try again."
    case AppleSignInError.unavailable:
      return "Apple sign-in is unavailable right now. Try again later or continue with email."
    case APIError.conflict:
      return "An account already uses this email. Sign in with its existing method, then connect Apple in web Account settings."
    case APIError.emailUnverified:
      return "Verify your account before signing in. You can request a new verification email with the email method."
    case APIError.offline:
      return APIError.offlineMessage
    default:
      return "Organized Glitter could not sign you in with Apple. Try again."
    }
  }

  func signInWithOAuth(provider: SocialProvider, anchor: ASPresentationAnchor) {
    guard !isSigningOut, !cleanupBlocked, !isSubmitting,
      client != nil, socialProviders.contains(provider) else { return }
    let browser = OAuthWebSession(anchor: anchor)
    signInWithOAuth(
      provider: provider,
      present: { try await browser.start($0, redirectURL: $1) }
    )
    if oauthTask != nil { oauthBrowser = browser }
  }

  func signInWithOAuth(
    provider: SocialProvider,
    present: @escaping @MainActor @Sendable (URL, URL) async throws -> URL,
    timeout: Duration = .seconds(120)
  ) {
    guard !isSigningOut, !cleanupBlocked, !isSubmitting,
      let client, socialProviders.contains(provider) else { return }
    let generation = beginSessionTransition()
    let attemptID = UUID()
    oauthAttemptID = attemptID
    isSubmitting = true
    oauthError = nil
    oauthTask = Task {
      defer {
        if generation == sessionGeneration {
          isSubmitting = false
          oauthBrowser?.cancel()
          oauthBrowser = nil
          oauthTimeoutTask?.cancel()
          oauthTimeoutTask = nil
          oauthTask = nil
          oauthAttemptID = nil
        }
      }
      do {
        let session = try await client.signInWithOAuth(
          providerName: provider.rawValue,
          attemptID: attemptID,
          present: present
        )
        guard generation == sessionGeneration else { return }
        try await openLibrary(for: session.user, generation: generation)
        guard generation == sessionGeneration else { return }
        phase = .signedIn(session.user)
        applyThemePreference(from: session.user)
      } catch is CancellationError {
        return
      } catch APIError.cancelled {
        return
      } catch {
        guard generation == sessionGeneration else { return }
        oauthError = Self.oauthMessage(for: error)
      }
    }
    oauthTimeoutTask = Task {
      try? await Task.sleep(for: timeout)
      guard !Task.isCancelled, generation == sessionGeneration else { return }
      cancelOAuth()
      oauthError = "Sign-in timed out. Try again."
    }
  }

  func cancelOAuth() {
    guard oauthTask != nil else { return }
    _ = beginSessionTransition()
    isSubmitting = false
  }

  private static func oauthMessage(for error: Error) -> String {
    switch error {
    case OAuthError.unavailable:
      return "This sign-in provider is unavailable right now."
    case OAuthError.denied:
      return "The provider did not approve sign-in. Try again."
    case OAuthError.invalidResponse:
      return "The provider did not complete sign-in. Try again."
    case OAuthError.presentationFailed:
      return "The sign-in window could not open. Try again."
    case APIError.conflict:
      return "This sign-in conflicts with an existing account. Sign in with your existing method and manage connections on the web."
    case APIError.emailUnverified:
      return "Verify your account before signing in. You can request a new verification email with the email method."
    case APIError.offline:
      return APIError.offlineMessage
    default:
      return "Organized Glitter could not sign you in. Try again."
    }
  }

  func expireSession() async {
    guard !isSigningOut else { return }
    isSigningOut = true
    defer { isSigningOut = false }
    sessionGeneration &+= 1
    library?.pauseWrites()
    await drainUserSave()
    await client?.signOut()
    try? await library?.close(removingData: false)
    library = nil
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
        await library?.waitForWrites()
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
    isSubmitting = false
    signInError = nil
    await expireSession()
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
  /// `theme_palette` is iOS-only; unknown values keep the device palette.
  private func applyThemePreference(from user: UserRecord) {
    guard let themeStore else {
      return
    }
    if let flavor = user.themePreference.flatMap(ThemeFlavor.init(rawValue:)) {
      themeStore.flavor = flavor
    }
    if let palette = user.themePalette.flatMap(ThemePalette.init(rawValue:)) {
      themeStore.palette = palette
    }
  }

  private func beginSessionTransition() -> Int {
    oauthTask?.cancel()
    if let attemptID = oauthAttemptID {
      Task { await client?.cancelExternalAuthAttempt(id: attemptID) }
    }
    oauthAttemptID = nil
    oauthTimeoutTask?.cancel()
    oauthBrowser?.cancel()
    oauthTask = nil
    oauthTimeoutTask = nil
    oauthBrowser = nil
    appleTimeoutTask?.cancel()
    appleTimeoutTask = nil
    appleTask?.cancel()
    appleTask = nil
    appleAttempt = nil
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
    case .conflict:
      return "This account conflicts with an existing sign-in method."
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
