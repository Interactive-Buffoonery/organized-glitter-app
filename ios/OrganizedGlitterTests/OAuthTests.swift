import Foundation
import Testing
@testable import OrganizedGlitter

@Suite(.serialized)
struct OAuthTests {
  @Test
  func preservesProviderPKCEAndEncodesBackendRedirect() throws {
    let provider = OAuthProvider(
      name: "google",
      authURL: "https://accounts.example.test/authorize?code_challenge=challenge&code_challenge_method=S256&redirect_uri=",
      codeVerifier: "verifier"
    )
    let redirect = URL(string: "https://data.example.test/api/oauth2-redirect")!
    let url = try provider.authorizationURL(redirectURL: redirect, clientID: "client + id")
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

    #expect(query.first(where: { $0.name == "redirect_uri" })?.value == redirect.absoluteString)
    #expect(query.first(where: { $0.name == "code_challenge" })?.value == "challenge")
    #expect(query.first(where: { $0.name == "code_challenge_method" })?.value == "S256")
    #expect(query.first(where: { $0.name == "state" })?.value == "client + id")
  }

  @Test
  func parsesPocketBaseConnectionAndOAuthCallback() throws {
    var parser = OAuthSSEParser()
    #expect(try parser.consume("event: PB_CONNECT") == nil)
    #expect(try parser.consume("id: client-1") == nil)
    #expect(try parser.consume("") == .connected("client-1"))
    #expect(try parser.consume("event: @oauth2") == nil)
    #expect(try parser.consume(#"data: {"state":"client-1","code":"code-1"}"#) == nil)
    #expect(
      try parser.consume("")
        == .callback(OAuthCallback(state: "client-1", code: "code-1", error: nil))
    )
    #expect(throws: OAuthError.invalidResponse) {
      _ = try parser.consume("event: @oauth2")
      _ = try parser.consume("data: invalid")
      _ = try parser.consume("")
    }
  }

  @Test
  func rejectsCumulativeOversizedSSEPayload() throws {
    var parser = OAuthSSEParser()
    _ = try parser.consume("event: @oauth2")
    _ = try parser.consume("data: \(String(repeating: "a", count: 5_000))")
    #expect(throws: OAuthError.invalidResponse) {
      _ = try parser.consume("data: \(String(repeating: "b", count: 5_000))")
    }
  }

  @Test
  func urlSessionByteStreamPreservesSSEEventBoundaries() async throws {
    OAuthHTTP.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OAuthHTTP.self]
    let session = URLSession(configuration: configuration)
    let connection = OAuthRealtime.open(
      url: URL(string: "https://data.example.test/api/realtime")!,
      session: session
    )
    defer { connection.cancel() }
    var iterator = connection.events.makeAsyncIterator()
    #expect(try await iterator.next() == .connected("client-1"))
    #expect(
      try await iterator.next()
        == .callback(OAuthCallback(state: "client-1", code: "code-1", error: nil))
    )
    await #expect(throws: OAuthError.disconnected) { _ = try await iterator.next() }
  }

  @MainActor
  @Test
  func subscribesBeforePresentationAndExchangesAsGuest() async throws {
    OAuthHTTP.reset()
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.oauth-tests.\(UUID().uuidString)"
    )
    defer { try? store.clear() }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OAuthHTTP.self]
    let (stream, continuation) = AsyncThrowingStream<OAuthRealtimeEvent, Error>.makeStream()
    let client = PocketBaseClient(
      baseURL: URL(string: "https://data.example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration),
      oauthEvents: { _, _ in OAuthRealtime.Connection(events: stream, stop: {}) }
    )
    continuation.yield(.connected("client-1"))
    let presentation = OAuthPresentation()
    let task = Task {
      try await client.signInWithOAuth(
        providerName: "google",
        present: { url in
          #expect(OAuthHTTP.paths().contains("POST /api/realtime"))
          presentation.url = url
          continuation.yield(.callback(OAuthCallback(state: "client-1", code: "code-1", error: nil)))
        },
        dismissAccepted: { presentation.dismissed = true }
      )
    }
    let session = try await task.value

    #expect(session.user.id == "user-1")
    #expect(presentation.dismissed)
    #expect(try store.load()?.token == "test-token")
    #expect(OAuthHTTP.paths() == [
      "GET /api/collections/users/auth-methods",
      "POST /api/realtime",
      "POST /api/collections/users/auth-with-oauth2",
    ])
    let url = try #require(presentation.url)
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.first(where: { $0.name == "state" })?.value == "client-1")
    let exchange = try #require(OAuthHTTP.exchangeBody())
    #expect(exchange["provider"] as? String == "google")
    #expect(exchange["codeVerifier"] as? String == "verifier-1")
    #expect(exchange["redirectURL"] as? String == "https://data.example.test/api/oauth2-redirect")
    #expect(OAuthHTTP.exchangeAuthorization() == nil)
    await client.signOut()
    continuation.finish()
  }

  @MainActor
  @Test
  func rejectsWrongStateBeforeExchangeOrPersistence() async throws {
    OAuthHTTP.reset()
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.oauth-tests.\(UUID().uuidString)"
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OAuthHTTP.self]
    let (stream, continuation) = AsyncThrowingStream<OAuthRealtimeEvent, Error>.makeStream()
    let client = PocketBaseClient(
      baseURL: URL(string: "https://data.example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration),
      oauthEvents: { _, _ in OAuthRealtime.Connection(events: stream, stop: {}) }
    )
    continuation.yield(.connected("client-1"))
    await #expect(throws: OAuthError.invalidResponse) {
      _ = try await client.signInWithOAuth(
        providerName: "discord",
        present: { _ in
          continuation.yield(.callback(OAuthCallback(state: "other-client", code: "code-1", error: nil)))
        },
        dismissAccepted: {}
      )
    }
    #expect(!OAuthHTTP.paths().contains("POST /api/collections/users/auth-with-oauth2"))
    #expect(try store.load() == nil)
    continuation.finish()
  }

  @MainActor
  @Test
  func signOutDuringExchangeCannotPersistLateOAuthResponse() async throws {
    OAuthHTTP.reset()
    OAuthHTTP.holdExchange()
    defer { OAuthHTTP.releaseExchange() }
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.oauth-tests.\(UUID().uuidString)"
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OAuthHTTP.self]
    let (stream, continuation) = AsyncThrowingStream<OAuthRealtimeEvent, Error>.makeStream()
    let client = PocketBaseClient(
      baseURL: URL(string: "https://data.example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration),
      oauthEvents: { _, _ in OAuthRealtime.Connection(events: stream, stop: {}) }
    )
    continuation.yield(.connected("client-1"))
    let task = Task {
      try await client.signInWithOAuth(
        providerName: "google",
        present: { _ in
          continuation.yield(.callback(OAuthCallback(state: "client-1", code: "code-1", error: nil)))
        },
        dismissAccepted: {}
      )
    }
    while !OAuthHTTP.paths().contains("POST /api/collections/users/auth-with-oauth2") {
      await Task.yield()
    }
    await client.signOut()
    OAuthHTTP.releaseExchange()
    await #expect(throws: APIError.cancelled) { _ = try await task.value }
    #expect(try store.load() == nil)
    continuation.finish()
  }

  @MainActor
  @Test(arguments: [false, true])
  func cancellingModelRejectsLateResultAndAllowsRetry(duringExchange: Bool) async throws {
    OAuthHTTP.reset()
    if duringExchange { OAuthHTTP.holdExchange() }
    defer { OAuthHTTP.releaseExchange() }
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.oauth-tests.\(UUID().uuidString)"
    )
    defer { try? store.clear() }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OAuthHTTP.self]
    let (stream, continuation) = AsyncThrowingStream<OAuthRealtimeEvent, Error>.makeStream()
    let (stops, stopped) = AsyncStream<Void>.makeStream()
    let client = PocketBaseClient(
      baseURL: URL(string: "https://data.example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration),
      oauthEvents: { _, _ in
        OAuthRealtime.Connection(events: stream, stop: { stopped.yield(()) })
      }
    )
    let model = AppModel(client: client, sessionStore: store, themeStore: ThemeStore())
    while model.phase == .restoring { await Task.yield() }
    model.socialProviders = [.google]
    let presentation = OAuthPresentation()
    continuation.yield(.connected("client-1"))
    model.signInWithOAuth(
      provider: .google,
      present: { presentation.url = $0 },
      dismissAccepted: { presentation.dismissed = true }
    )
    while presentation.url == nil { await Task.yield() }

    if duringExchange {
      continuation.yield(.callback(OAuthCallback(state: "client-1", code: "code-1", error: nil)))
      while !OAuthHTTP.paths().contains("POST /api/collections/users/auth-with-oauth2") {
        await Task.yield()
      }
    }
    model.cancelOAuth()
    OAuthHTTP.releaseExchange()
    continuation.yield(.callback(OAuthCallback(state: "client-1", code: "late-code", error: nil)))
    var stoppedIterator = stops.makeAsyncIterator()
    await stoppedIterator.next()

    #expect(model.phase == .signedOut)
    #expect(!model.isSubmitting)
    #expect(presentation.dismissed == duringExchange)
    #expect(try store.load() == nil)
    #expect(OAuthHTTP.paths().contains("POST /api/collections/users/auth-with-oauth2") == duringExchange)
    continuation.finish()
    stopped.finish()

    let retry = await client.beginExternalAuthAttempt()
    let response = AuthResponse(token: "retry-token", record: .preview)
    _ = try await client.acceptExternalAuthResponse(response, attempt: retry)
    #expect(try store.load()?.token == "retry-token")
  }

  @MainActor
  @Test
  func timeoutEndsModelAttemptWithoutPublishingSession() async throws {
    OAuthHTTP.reset()
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.oauth-tests.\(UUID().uuidString)"
    )
    defer { try? store.clear() }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OAuthHTTP.self]
    let (stream, continuation) = AsyncThrowingStream<OAuthRealtimeEvent, Error>.makeStream()
    defer { continuation.finish() }
    let client = PocketBaseClient(
      baseURL: URL(string: "https://data.example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration),
      oauthEvents: { _, _ in OAuthRealtime.Connection(events: stream, stop: {}) }
    )
    let model = AppModel(client: client, sessionStore: store, themeStore: ThemeStore())
    while model.phase == .restoring { await Task.yield() }
    model.socialProviders = [.google]
    model.signInWithOAuth(provider: .google, present: { _ in }, dismissAccepted: {}, timeout: .zero)
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

  @MainActor
  @Test
  func providerDenialClosesAttemptBeforeExchange() async throws {
    OAuthHTTP.reset()
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.oauth-tests.\(UUID().uuidString)"
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OAuthHTTP.self]
    let (stream, continuation) = AsyncThrowingStream<OAuthRealtimeEvent, Error>.makeStream()
    let client = PocketBaseClient(
      baseURL: URL(string: "https://data.example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration),
      oauthEvents: { _, _ in OAuthRealtime.Connection(events: stream, stop: {}) }
    )
    continuation.yield(.connected("client-1"))
    await #expect(throws: OAuthError.denied) {
      _ = try await client.signInWithOAuth(
        providerName: "google",
        present: { _ in
          continuation.yield(.callback(OAuthCallback(state: "client-1", code: nil, error: "access_denied")))
        },
        dismissAccepted: {}
      )
    }
    #expect(!OAuthHTTP.paths().contains("POST /api/collections/users/auth-with-oauth2"))
    #expect(try store.load() == nil)
    continuation.finish()
  }
}

@MainActor
private final class OAuthPresentation {
  var url: URL?
  var dismissed = false
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
    case "/api/realtime":
      body = request.httpMethod == "GET"
        ? "event: PB_CONNECT\nid: client-1\ndata: {}\n\nevent: @oauth2\ndata: {\"state\":\"client-1\",\"code\":\"code-1\"}\n\n"
        : "{}"
    case "/api/collections/users/auth-with-oauth2":
      body = #"{"token":"test-token","record":{"id":"user-1","verified":true}}"#
    default:
      body = "{}"
    }
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: request.httpMethod == "GET" && request.url?.path == "/api/realtime"
        ? ["Content-Type": "text/event-stream"] : nil
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
