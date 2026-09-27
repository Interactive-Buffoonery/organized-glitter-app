import Foundation
import Testing
@testable import OrganizedGlitter

@MainActor
@Suite(.serialized)
struct AppModelTests {
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
