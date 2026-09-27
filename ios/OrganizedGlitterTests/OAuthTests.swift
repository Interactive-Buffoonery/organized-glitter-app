import Foundation
import Testing
@testable import OrganizedGlitter

@Suite(.serialized)
struct OAuthTests {
  @MainActor
  private func makeClient(_ store: KeychainSessionStore) -> PocketBaseClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OAuthHTTP.self]
    return PocketBaseClient(
      baseURL: URL(string: "https://data.example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration)
    )
  }

  @MainActor
  @Test
  func directCallbackPreservesPKCEAndExchangesAsGuestWithoutRealtime() async throws {
    OAuthHTTP.reset()
    let store = KeychainSessionStore(service: "oauth-tests.\(UUID().uuidString)")
    defer { try? store.clear() }
    let client = makeClient(store)
    let session = try await client.signInWithOAuth(providerName: "google") { url, redirect in
      let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
      #expect(query.first(where: { $0.name == "state" })?.value == "initial")
      #expect(query.first(where: { $0.name == "code_challenge" })?.value == "challenge")
      #expect(query.first(where: { $0.name == "redirect_uri" })?.value == redirect.absoluteString)
      return URL(string: "\(redirect.absoluteString)?state=initial&code=test-code")!
    }
    #expect(session.user.id == "user-1")
    #expect(try store.load()?.token == "test-token")
    #expect(OAuthHTTP.paths() == [
      "GET /api/collections/users/auth-methods",
      "POST /api/collections/users/auth-with-oauth2",
    ])
    let exchange = try #require(OAuthHTTP.exchangeBody())
    #expect(exchange["provider"] as? String == "google")
    #expect(exchange["code"] as? String == "test-code")
    #expect(exchange["codeVerifier"] as? String == "verifier-1")
    #expect(exchange["redirectURL"] as? String == "https://data.example.test/api/oauth2-redirect")
    #expect(OAuthHTTP.exchangeAuthorization() == nil)
  }

  @MainActor
  @Test(arguments: [
    "https://data.example.test/api/oauth2-redirect?state=wrong&code=test-code",
    "https://data.example.test/api/oauth2-redirect?code=test-code",
    "https://data.example.test/api/oauth2-redirect?state=initial",
    "https://data.example.test/api/oauth2-redirect?state=initial&code=",
    "https://other.example.test/api/oauth2-redirect?state=initial&code=test-code",
    "http://data.example.test/api/oauth2-redirect?state=initial&code=test-code",
    "https://data.example.test/wrong?state=initial&code=test-code",
    "https://data.example.test:444/api/oauth2-redirect?state=initial&code=test-code",
    "https://data.example.test/api/oauth2-redirect?state=initial&state=other&code=test-code",
    "https://data.example.test/api/oauth2-redirect?state=initial&code=one&code=two",
  ])
  func rejectsInvalidCallbackBeforeExchangeOrPersistence(callback: String) async throws {
    OAuthHTTP.reset()
    let store = KeychainSessionStore(service: "oauth-tests.\(UUID().uuidString)")
    defer { try? store.clear() }
    let client = makeClient(store)
    await #expect(throws: OAuthError.invalidResponse) {
      _ = try await client.signInWithOAuth(providerName: "discord") { _, _ in URL(string: callback)! }
    }
    #expect(OAuthHTTP.exchangeBody() == nil)
    #expect(try store.load() == nil)
  }

  @MainActor
  @Test
  func providerDenialPreventsExchange() async throws {
    OAuthHTTP.reset()
    let store = KeychainSessionStore(service: "oauth-tests.\(UUID().uuidString)")
    let client = makeClient(store)
    await #expect(throws: OAuthError.denied) {
      _ = try await client.signInWithOAuth(providerName: "google") { _, redirect in
        URL(string: "\(redirect.absoluteString)?state=initial&error=access_denied")!
      }
    }
    #expect(OAuthHTTP.exchangeBody() == nil)
    #expect(try store.load() == nil)
  }

  @MainActor
  @Test
  func signOutDuringExchangeRejectsLateResponse() async throws {
    OAuthHTTP.reset()
    OAuthHTTP.holdExchange()
    defer { OAuthHTTP.releaseExchange() }
    let store = KeychainSessionStore(service: "oauth-tests.\(UUID().uuidString)")
    defer { try? store.clear() }
    let client = makeClient(store)
    let task = Task {
      try await client.signInWithOAuth(providerName: "google") { _, redirect in
        URL(string: "\(redirect.absoluteString)?state=initial&code=test-code")!
      }
    }
    while OAuthHTTP.exchangeBody() == nil { await Task.yield() }
    await client.signOut()
    OAuthHTTP.releaseExchange()
    await #expect(throws: APIError.cancelled) { _ = try await task.value }
    #expect(try store.load() == nil)
  }

  @MainActor
  @Test(arguments: [false, true])
  func cancellingModelRejectsLateResultAndAllowsRetry(duringExchange: Bool) async throws {
    OAuthHTTP.reset()
    if duringExchange { OAuthHTTP.holdExchange() }
    defer { OAuthHTTP.releaseExchange() }
    let store = KeychainSessionStore(service: "oauth-tests.\(UUID().uuidString)")
    defer { try? store.clear() }
    let client = makeClient(store)
    let model = AppModel(client: client, sessionStore: store, themeStore: ThemeStore())
    while model.phase == .restoring { await Task.yield() }
    model.socialProviders = [.google]
    let presentation = OAuthPresentation()
    model.signInWithOAuth(provider: .google, present: { _, redirect in
      defer { presentation.finished = true }
      if duringExchange {
        return URL(string: "\(redirect.absoluteString)?state=initial&code=test-code")!
      }
      return await withCheckedContinuation { presentation.continuation = $0 }
    })
    while duringExchange ? OAuthHTTP.exchangeBody() == nil : presentation.continuation == nil {
      await Task.yield()
    }
    model.cancelOAuth()
    OAuthHTTP.releaseExchange()
    presentation.continuation?.resume(returning: URL(string:
      "https://data.example.test/api/oauth2-redirect?state=initial&code=late-code"
    )!)
    while !presentation.finished { await Task.yield() }
    // Await a subsequent actor call so callback validation has an opportunity to run.
    let retry = await client.beginExternalAuthAttempt()
    #expect(model.phase == .signedOut)
    #expect(!model.isSubmitting)
    #expect(try store.load() == nil)
    #expect((OAuthHTTP.exchangeBody() != nil) == duringExchange)
    _ = try await client.acceptExternalAuthResponse(
      AuthResponse(token: "retry-token", record: .preview), attempt: retry
    )
    #expect(try store.load()?.token == "retry-token")
  }

  @MainActor
  @Test
  func timeoutEndsModelAttemptWithoutPublishingSession() async throws {
    OAuthHTTP.reset()
    let store = KeychainSessionStore(service: "oauth-tests.\(UUID().uuidString)")
    defer { try? store.clear() }
    let model = AppModel(client: makeClient(store), sessionStore: store, themeStore: ThemeStore())
    while model.phase == .restoring { await Task.yield() }
    model.socialProviders = [.google]
    model.signInWithOAuth(provider: .google, present: { _, _ in
      try await Task.sleep(for: .seconds(30))
      throw CancellationError()
    }, timeout: .zero)
    while model.isSubmitting { await Task.yield() }
    #expect(model.phase == .signedOut)
    #expect(model.oauthError == "Sign-in timed out. Try again.")
    #expect(try store.load() == nil)
  }

  @Test
  func cancellingAttemptRejectsLateResponseWithoutTaskCancellation() async throws {
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.oauth-tests.\(UUID().uuidString)"
    )
    defer { try? store.clear() }
    let client = PocketBaseClient(baseURL: URL(string: "https://data.example.test")!, sessionStore: store)
    let id = UUID()
    let attempt = await client.beginExternalAuthAttempt(id: id)
    await client.cancelExternalAuthAttempt(id: id)

    await #expect(throws: APIError.cancelled) {
      _ = try await client.acceptExternalAuthResponse(
        AuthResponse(token: "late-token", record: .preview), attempt: attempt
      )
    }
    #expect(try store.load() == nil)
  }

  @Test
  func delayedCancellationDoesNotInvalidateNewerAttempt() async throws {
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.oauth-tests.\(UUID().uuidString)"
    )
    defer { try? store.clear() }
    let client = PocketBaseClient(baseURL: URL(string: "https://data.example.test")!, sessionStore: store)
    let oldID = UUID()
    let oldAttempt = await client.beginExternalAuthAttempt(id: oldID)
    let retry = await client.beginExternalAuthAttempt()
    await client.cancelExternalAuthAttempt(id: oldID)

    await #expect(throws: APIError.cancelled) {
      _ = try await client.acceptExternalAuthResponse(
        AuthResponse(token: "old-token", record: .preview), attempt: oldAttempt
      )
    }
    _ = try await client.acceptExternalAuthResponse(
      AuthResponse(token: "retry-token", record: .preview), attempt: retry
    )
    #expect(try store.load()?.token == "retry-token")
  }

}

@MainActor
private final class OAuthPresentation {
  var continuation: CheckedContinuation<URL, Never>?
  var finished = false
}

private final class OAuthHTTP: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var captured: [URLRequest] = []
  nonisolated(unsafe) private static var bodies: [Data] = []
  nonisolated(unsafe) private static var exchangeGate: DispatchSemaphore?

  static func reset() {
    lock.lock()
    defer { lock.unlock() }
    captured = []
    bodies = []
    exchangeGate = nil
  }

  static func holdExchange() {
    lock.lock()
    exchangeGate = DispatchSemaphore(value: 0)
    lock.unlock()
  }

  static func releaseExchange() {
    lock.lock()
    let gate = exchangeGate
    exchangeGate = nil
    lock.unlock()
    gate?.signal()
  }

  static func paths() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return captured.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" }
  }

  static func exchangeBody() -> [String: Any]? {
    lock.lock()
    defer { lock.unlock() }
    guard let index = captured.firstIndex(where: { $0.url?.path.hasSuffix("auth-with-oauth2") == true }) else { return nil }
    return try? JSONSerialization.jsonObject(with: bodies[index]) as? [String: Any]
  }

  static func exchangeAuthorization() -> String? {
    lock.lock()
    defer { lock.unlock() }
    return captured.first(where: { $0.url?.path.hasSuffix("auth-with-oauth2") == true })?
      .value(forHTTPHeaderField: "Authorization")
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.lock()
    Self.captured.append(request)
    Self.bodies.append(bodyData)
    let gate = request.url?.path == "/api/collections/users/auth-with-oauth2" ? Self.exchangeGate : nil
    Self.lock.unlock()
    _ = gate?.wait(timeout: .now() + 3)
    let body: String
    switch request.url?.path {
    case "/api/collections/users/auth-methods":
      body = #"{"oauth2":{"enabled":true,"providers":[{"name":"google","state":"initial","authURL":"https://accounts.example.test/authorize?code_challenge=challenge&redirect_uri=","codeVerifier":"verifier-1"},{"name":"discord","state":"initial","authURL":"https://discord.example.test/authorize?code_challenge=challenge&redirect_uri=","codeVerifier":"verifier-2"}]}}"#
    case "/api/collections/users/auth-with-oauth2":
      body = #"{"token":"test-token","record":{"id":"user-1","verified":true}}"#
    default:
      body = "{}"
    }
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: nil
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private var bodyData: Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while true {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { return result }
      result.append(buffer, count: count)
    }
  }
}
