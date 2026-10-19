import AuthenticationServices
import Foundation
import Testing
@testable import OrganizedGlitter

@MainActor
@Suite(.serialized)
struct AppModelTests {
  @Test
  func explicitLocalRemovalPreservesOtherBackendLibraries() async throws {
    let local = try LocalLibraryStore.inMemory()
    let backend = URL(string: "https://example.test")!
    let scope = LocalAccountScope(backendURL: backend, userID: UserRecord.preview.id)
    let other = LocalAccountScope(backendURL: URL(string: "https://other.test")!, userID: UserRecord.preview.id)
    try await local.saveUser(.preview, scope: scope)
    try await local.saveUser(.preview, scope: other)
    let store = KeychainSessionStore(service: "deletion.explicit.\(UUID().uuidString)")
    let client = PocketBaseClient(baseURL: backend, sessionStore: store)
    let model = AppModel(client: client, sessionStore: store, themeStore: ThemeStore(), localStore: local)
    while model.phase == .restoring { await Task.yield() }
    await model.loadRemovableLocalScopes()
    #expect(try await local.loadUser(scope: scope) != nil)
    #expect(model.removableLocalScopeCount == 1)
    await model.removeSavedLibrariesFromDevice()
    #expect(try await local.loadUser(scope: scope) == nil)
    #expect(try await local.loadUser(scope: other) != nil)
    #expect(try await local.pendingRemovals().isEmpty)
    #expect(model.phase == .signedOut)
  }

  @Test
  func submittedDeletionRecoveryPrecedesSessionRestoration() async throws {
    let store = KeychainSessionStore(service: "deletion.recovery.\(UUID().uuidString)")
    let url = URL(string: "https://example.test")!
    let client = PocketBaseClient(baseURL: url, sessionStore: store)
    var intent = AccountDeletionIntent(backendURL: url, userID: "user-a", proof: try AccountDeletionIntent.makeProof())
    intent.stage = .submitted
    let persistence = AccountDeletionPersistence(load: { intent }, save: { _ in }, clear: {})
    let model = AppModel(client: client, sessionStore: store, themeStore: ThemeStore(), deletionPersistence: persistence)
    while model.phase == .restoring { await Task.yield() }
    #expect(model.phase == .accountDeletion)
    #expect(model.deletion?.state == .uncertain)
    #expect(model.library == nil)
    await model.signIn(identity: "example", password: "example")
    #expect(model.phase == .accountDeletion)
    await model.expireSession()
    #expect(model.phase == .accountDeletion)
  }

  @Test
  func recoveryRejectsCredentialsForADifferentAccount() throws {
    let store = KeychainSessionStore(service: "deletion.identity.\(UUID().uuidString)")
    defer { try? store.clear() }
    try store.save(AuthenticatedSession(token: "fictional", user: .preview))
    let url = URL(string: "https://example.test")!
    let client = PocketBaseClient(baseURL: url, sessionStore: store)
    var intent = AccountDeletionIntent(backendURL: url, userID: "different-account", proof: try AccountDeletionIntent.makeProof())
    intent.stage = .submitted
    let persistence = AccountDeletionPersistence(load: { intent }, save: { _ in }, clear: {})
    let model = AppModel(client: client, sessionStore: store, themeStore: ThemeStore(), deletionPersistence: persistence)
    #expect(model.phase == .accountDeletion)
    #expect(model.deletion == nil)
    #expect(try store.load()?.userID == UserRecord.preview.id)
  }

  @Test
  func unreadableDeletionIntentBlocksLoginWithoutRemovingData() async throws {
    let store = KeychainSessionStore(service: "deletion.read.\(UUID().uuidString)")
    let client = PocketBaseClient(baseURL: URL(string: "https://example.test")!, sessionStore: store)
    let persistence = AccountDeletionPersistence(load: { throw APIError.decoding }, save: { _ in }, clear: {})
    let model = AppModel(client: client, sessionStore: store, themeStore: ThemeStore(), deletionPersistence: persistence)
    while model.phase == .restoring { await Task.yield() }
    #expect(model.phase == .accountDeletion)
    #expect(model.library == nil)
    await model.signIn(identity: "example", password: "example")
    #expect(model.phase == .accountDeletion)
  }

  @Test
  func appleSignInStartsAfterReadinessSucceeds() async throws {
    AppleReadinessURLProtocol.status = 200
    AppleReadinessURLProtocol.body = #"{"available":true}"#
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AppleReadinessURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration)
    )
    let model = AppModel(client: client, sessionStore: store, themeStore: ThemeStore())
    while model.phase == .restoring { await Task.yield() }

    await model.loadSignInMethods()
    #expect(model.appleReadiness == .available)
    let request = ASAuthorizationAppleIDProvider().createRequest()
    model.configureAppleRequest(request, sourceID: UUID())
    #expect(request.state != nil)
    #expect(request.nonce != nil)
    #expect(model.isSubmitting)
    model.cancelAppleSignIn()
  }

  @Test
  func appleSignInStaysUnavailableUntilReadinessRetrySucceeds() async throws {
    AppleReadinessURLProtocol.status = 200
    AppleReadinessURLProtocol.body = #"{"available":false}"#
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AppleReadinessURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration)
    )
    let model = AppModel(client: client, sessionStore: store, themeStore: ThemeStore())
    while model.phase == .restoring { await Task.yield() }

    await model.loadAppleReadiness()
    #expect(model.appleReadiness == .unavailable)
    let unavailableRequest = ASAuthorizationAppleIDProvider().createRequest()
    model.configureAppleRequest(unavailableRequest, sourceID: UUID())
    #expect(unavailableRequest.state == nil)
    #expect(!model.isSubmitting)

    AppleReadinessURLProtocol.status = 503
    await model.loadAppleReadiness()
    #expect(model.appleReadiness == .failed)
    let failedRequest = ASAuthorizationAppleIDProvider().createRequest()
    model.configureAppleRequest(failedRequest, sourceID: UUID())
    #expect(failedRequest.state == nil)
    #expect(!model.isSubmitting)

    AppleReadinessURLProtocol.status = 200
    AppleReadinessURLProtocol.body = #"{"available":true}"#
    await model.loadAppleReadiness()
    #expect(model.appleReadiness == .available)
    let retryRequest = ASAuthorizationAppleIDProvider().createRequest()
    model.configureAppleRequest(retryRequest, sourceID: UUID())
    #expect(retryRequest.state != nil)
    model.cancelAppleSignIn()
  }

  @Test
  func appleReadinessFinishesOutsideSignedOutPhase() async throws {
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AppleReadinessURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!, sessionStore: store,
      urlSession: URLSession(configuration: configuration)
    )
    let model = AppModel(client: client, sessionStore: store, themeStore: ThemeStore())
    while model.phase == .restoring { await Task.yield() }
    model.phase = .restorationFailed

    AppleReadinessURLProtocol.status = 200
    AppleReadinessURLProtocol.body = #"{"available":true}"#
    await model.loadAppleReadiness()
    #expect(model.appleReadiness == .available)
    let request = ASAuthorizationAppleIDProvider().createRequest()
    model.configureAppleRequest(request, sourceID: UUID())
    #expect(request.state == nil)

    AppleReadinessURLProtocol.status = 503
    await model.loadAppleReadiness()
    #expect(model.appleReadiness == .failed)
    model.phase = .signedOut
    AppleReadinessURLProtocol.status = 200
    await model.loadAppleReadiness()
    #expect(model.appleReadiness == .available)
  }

  @Test
  func missingAppleCallbackTimesOutAndAllowsRetry() async throws {
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    )
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!, sessionStore: store
    )
    let model = AppModel(client: client, sessionStore: store, themeStore: ThemeStore())
    while model.phase == .restoring { await Task.yield() }
    model.appleReadiness = .available
    let sourceID = UUID()
    let request = ASAuthorizationAppleIDProvider().createRequest()
    model.configureAppleRequest(request, sourceID: sourceID, timeout: .zero)
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(5)
    while model.isSubmitting && clock.now < deadline { await Task.yield() }
    #expect(!model.isSubmitting)
    #expect(model.appleError == "Apple sign-in timed out. Try again.")
    model.completeAppleAuthorization(
      .authorized(state: request.state, code: "late-code", name: nil), sourceID: sourceID
    )
    #expect(try store.load() == nil)
    #expect(model.phase == .signedOut)

    let retry = ASAuthorizationAppleIDProvider().createRequest()
    model.configureAppleRequest(retry, sourceID: UUID())
    #expect(retry.state != nil)
    #expect(model.isSubmitting)
    #expect(model.appleError == nil)
    model.cancelAppleSignIn()
  }

  @Test
  func appleSignInOpensTheLocalLibrary() async throws {
    DelayedAuthenticationURLProtocol.reset()
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    )
    defer { try? store.clear() }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DelayedAuthenticationURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration)
    )
    let model = AppModel(client: client, sessionStore: store, themeStore: ThemeStore())
    while model.phase == .restoring { await Task.yield() }
    model.appleReadiness = .available

    let sourceID = UUID()
    let request = ASAuthorizationAppleIDProvider().createRequest()
    model.configureAppleRequest(request, sourceID: sourceID)
    model.completeAppleAuthorization(
      .authorized(state: request.state, code: "test-code", name: nil),
      sourceID: sourceID
    )

    for _ in 0..<100 where model.isSubmitting {
      try await Task.sleep(for: .milliseconds(20))
    }
    guard case .signedIn(let user) = model.phase else {
      Issue.record("Apple sign-in did not publish a session")
      return
    }
    #expect(model.library?.userID == user.id)
  }

  @Test
  func lateAppleCallbacksCannotClearANewerRequest() async throws {
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    )
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: store
    )
    let model = AppModel(client: client, sessionStore: store, themeStore: ThemeStore())
    while model.phase == .restoring {
      await Task.yield()
    }
    model.appleReadiness = .available

    let firstSource = UUID()
    let firstRequest = ASAuthorizationAppleIDProvider().createRequest()
    model.configureAppleRequest(firstRequest, sourceID: firstSource)
    let firstState = try #require(firstRequest.state)
    model.cancelAppleSignIn()

    let secondSource = UUID()
    let secondRequest = ASAuthorizationAppleIDProvider().createRequest()
    model.configureAppleRequest(secondRequest, sourceID: secondSource)
    let secondState = try #require(secondRequest.state)
    #expect(firstState != secondState)

    model.completeAppleAuthorization(.failed, sourceID: firstSource)
    #expect(model.isSubmitting)
    #expect(model.appleError == nil)

    model.completeAppleAuthorization(
      .authorized(state: firstState, code: "late-code", name: nil),
      sourceID: firstSource
    )
    #expect(model.isSubmitting)
    #expect(model.appleError == nil)

    model.completeAppleAuthorization(
      .authorized(state: firstState, code: "late-code", name: nil),
      sourceID: secondSource
    )
    #expect(!model.isSubmitting)
    #expect(model.appleError == "Apple did not provide a valid authorization. Try again.")

    let thirdSource = UUID()
    let thirdRequest = ASAuthorizationAppleIDProvider().createRequest()
    model.configureAppleRequest(thirdRequest, sourceID: thirdSource)
    #expect(thirdRequest.state != nil)
    #expect(model.isSubmitting)
    model.completeAppleAuthorization(
      .authorized(state: nil, code: "missing-state-code", name: nil),
      sourceID: thirdSource
    )
    #expect(!model.isSubmitting)
    #expect(model.appleError == "Apple did not provide a valid authorization. Try again.")
    #expect(try store.load() == nil)
  }

  @Test
  func preservesStoredSessionWhenRefreshHasServerFailure() async throws {
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    )
    try store.save(AuthenticatedSession(token: "test-token", user: .preview))

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ServerFailureURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration)
    )
    let model = AppModel(client: client, sessionStore: store, themeStore: ThemeStore())

    while model.phase == .restoring {
      await Task.yield()
    }

    #expect(model.phase == .restorationFailed)
    #expect(try store.load()?.token == "test-token")
    try store.clear()
  }

  /// The account still carries the web app's Catppuccin preference; iOS no
  /// longer has those flavors, so the retired value must be ignored and the
  /// device preference kept.
  @Test
  func ignoresRetiredCatppuccinAccountPreference() async throws {
    let suiteName = "AppModelTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    )
    try store.save(AuthenticatedSession(token: "test-token", user: .preview))

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MochaUserURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration)
    )
    let themeStore = ThemeStore(defaults: defaults)
    let model = AppModel(client: client, sessionStore: store, themeStore: themeStore)

    while model.phase == .restoring {
      await Task.yield()
    }

    if case .signedIn(let user) = model.phase {
      #expect(user.themePreference == "catppuccin-mocha")
    } else {
      Issue.record("expected signedIn phase")
    }
    #expect(themeStore.flavor == .system)
    try store.clear()
  }

  @Test
  func rejectsEmptySignInWithoutSubmitting() async throws {
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ServerFailureURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration)
    )
    let model = AppModel(client: client, sessionStore: store, themeStore: ThemeStore())
    model.phase = .signedOut

    await model.signIn(identity: "  ", password: "")

    #expect(model.phase == .signedOut)
    #expect(model.signInError == "Enter your email address and password.")
    #expect(model.isSubmitting == false)
  }

  @Test
  func routesOnlyCanonicalPasswordResetLinks() async throws {
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    )
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: store
    )
    let model = AppModel(client: client, sessionStore: store, themeStore: ThemeStore())
    model.phase = .signedOut

    model.open(
      try #require(
        URL(string: "https://example.test/auth/confirm-password-reset/not-ours")
      ))
    #expect(model.passwordResetDestination == nil)

    model.open(
      try #require(
        URL(string: "https://organizedglitter.app/auth/confirm-password-reset/opaque.token")
      ))
    #expect(model.passwordResetDestination?.link == .confirmation(token: "opaque.token"))
  }

  @Test
  func blocksPasswordResetWhileSignedIn() throws {
    let model = AppModel(configurationError: URLError(.badURL), themeStore: ThemeStore())
    model.phase = .signedIn(.preview)

    model.open(try #require(URL(string: "https://organizedglitter.app/auth/confirm-password-reset/token")))

    #expect(model.passwordResetDestination == nil)
    #expect(model.showsSignedInPasswordResetNotice)
    #expect(model.phase == .signedIn(.preview))
    model.showsSignedInPasswordResetNotice = false
    model.phase = .signedOut
    #expect(model.passwordResetDestination == nil)
  }

  @Test
  func refreshingSignedInUserDoesNotRepeatResetNotice() throws {
    let model = AppModel(configurationError: URLError(.badURL), themeStore: ThemeStore())
    model.phase = .signedOut
    model.open(try #require(URL(string: "https://organizedglitter.app/auth/confirm-password-reset/token")))
    model.phase = .signedIn(.preview)
    #expect(model.passwordResetDestination == nil)
    #expect(model.showsSignedInPasswordResetNotice)

    model.showsSignedInPasswordResetNotice = false
    model.replaceSignedInUser(.preview)

    #expect(!model.showsSignedInPasswordResetNotice)
    #expect(model.passwordResetDestination == nil)
    #expect(model.phase == .signedIn(.preview))

    model.open(try #require(URL(string: "https://organizedglitter.app/auth/confirm-password-reset/token")))
    #expect(model.showsSignedInPasswordResetNotice)
    model.showsSignedInPasswordResetNotice = false
    model.replaceSignedInUser(.preview)
    #expect(!model.showsSignedInPasswordResetNotice)
  }

  @Test(arguments: [true, false])
  func defersResetLinkUntilSessionRestorationFinishes(signedIn: Bool) throws {
    let model = AppModel(configurationError: URLError(.badURL), themeStore: ThemeStore())
    model.phase = .restoring
    model.open(try #require(URL(string: "https://organizedglitter.app/auth/confirm-password-reset/token")))
    #expect(model.passwordResetDestination == nil)
    #expect(!model.showsSignedInPasswordResetNotice)

    model.phase = signedIn ? .signedIn(.preview) : .signedOut

    #expect(model.showsSignedInPasswordResetNotice == signedIn)
    #expect(model.passwordResetDestination?.link == (signedIn ? nil : .confirmation(token: "token")))
  }

  @Test
  func dismissesResetFormWhenSignInFinishes() throws {
    let model = AppModel(configurationError: URLError(.badURL), themeStore: ThemeStore())
    model.phase = .signedOut
    model.open(try #require(URL(string: "https://organizedglitter.app/auth/confirm-password-reset/token")))
    #expect(model.passwordResetDestination != nil)

    model.phase = .signedIn(.preview)

    #expect(model.passwordResetDestination == nil)
    #expect(model.showsSignedInPasswordResetNotice)
  }

  @Test
  func passwordResetSupersedesAnInFlightSignIn() async throws {
    DelayedAuthenticationURLProtocol.reset()
    defer { DelayedAuthenticationURLProtocol.reset() }

    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    )
    defer { try? store.clear() }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DelayedAuthenticationURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration)
    )
    let model = AppModel(client: client, sessionStore: store, themeStore: ThemeStore())
    while model.phase == .restoring {
      await Task.yield()
    }

    let signIn = Task {
      await model.signIn(identity: "sarah@example.test", password: "password")
    }
    while DelayedAuthenticationURLProtocol.requests.isEmpty {
      await Task.yield()
    }

    await model.passwordResetConfirmed()
    await signIn.value

    #expect(model.phase == .signedOut)
    #expect(model.isSubmitting == false)
    #expect(model.signInError == nil)
    #expect(try store.load() == nil)
  }

  @Test
  func passwordResetSupersedesAnInFlightRestoreWithoutShowingAnError() async throws {
    DelayedAuthenticationURLProtocol.reset()
    defer { DelayedAuthenticationURLProtocol.reset() }

    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    )
    defer { try? store.clear() }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DelayedAuthenticationURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration)
    )
    let model = AppModel(client: client, sessionStore: store, themeStore: ThemeStore())
    while model.phase == .restoring {
      await Task.yield()
    }

    try store.save(AuthenticatedSession(token: "stored-token", user: .preview))
    model.phase = .restoring
    let restoration = Task {
      await model.restoreSession()
    }
    while DelayedAuthenticationURLProtocol.requests.isEmpty {
      await Task.yield()
    }

    await model.passwordResetConfirmed()
    await restoration.value

    #expect(model.phase == .signedOut)
    #expect(try store.load() == nil)
  }
}

private final class AppleReadinessURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var status = 200
  nonisolated(unsafe) static var body = #"{"available":true}"#

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let isReadiness = request.url?.path == "/api/auth/apple/native/readiness"
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: isReadiness ? Self.status : 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    let body = isReadiness ? Self.body : #"{"oauth2":{"enabled":false,"providers":[]}}"#
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private final class DelayedAuthenticationURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var requests: [URLRequest] = []

  static func reset() {
    requests = []
  }

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    Self.requests.append(request)
    Thread.sleep(forTimeInterval: 0.1)

    let body =
      #"{"token":"response-token","record":{"id":"user-1","email":"sarah@example.test","verified":true}}"#
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private final class MochaUserURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let body = """
      {
        "token": "refreshed-token",
        "record": {
          "id": "preview-user",
          "email": "sarah@example.test",
          "name": "Sarah",
          "theme_preference": "catppuccin-mocha"
        }
      }
      """
    let data = Data(body.utf8)
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private final class ServerFailureURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 500,
      httpVersion: nil,
      headerFields: nil
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data())
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
