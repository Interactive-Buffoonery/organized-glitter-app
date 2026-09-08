import Foundation
import Testing
@testable import OrganizedGlitter

@MainActor
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
