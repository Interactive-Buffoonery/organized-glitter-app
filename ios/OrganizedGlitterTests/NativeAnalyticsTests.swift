import Foundation
import PostHog
import Testing

@testable import OrganizedGlitter

@MainActor
@Suite(.serialized)
struct NativeAnalyticsTests {
  @Test func accountConsentMustBeFreshlyVerifiedBeforeCapture() {
    let analytics = NativeAnalytics()
    #expect(!analytics.isEnabled)
    analytics.setSession(accountID: "account-a", isActive: true, analyticsEnabled: nil)
    analytics.capture(.appOpened)
    #expect(!analytics.isEnabled)
    analytics.setSession(accountID: "account-a", isActive: true, analyticsEnabled: true)
    #expect(analytics.isEnabled)
    analytics.setSession(accountID: "account-a", isActive: true, analyticsEnabled: false)
    #expect(!analytics.isEnabled)
  }

  @Test func freshAccountWithoutAnalyticsFieldRemainsDisabled() async throws {
    let fixture = makeFixture()
    defer { fixture.close() }
    let user = try JSONDecoder().decode(
      UserRecord.self,
      from: Data(#"{"id":"account-a","verified":true}"#.utf8))
    let store = KeychainSessionStore(service: "analytics.missing-field.tests.\(UUID().uuidString)")
    defer { try? store.clear() }
    let client = PocketBaseClient(baseURL: URL(string: "https://example.test")!, sessionStore: store)
    let model = AppModel(
      client: client, sessionStore: store, themeStore: ThemeStore(), analytics: fixture.analytics)
    while model.phase == .restoring { await Task.yield() }
    model.phase = .signedIn(user)
    model.replaceSignedInUser(user)

    #expect(!fixture.analytics.isEnabled)
  }

  @Test func configurationRejectsProductionDebugAndInvalidDestinations() {
    #expect(configuration(isDebug: true, environment: "production") == nil)
    #expect(configuration(host: "http://example.test") == nil)
    #expect(configuration(host: "https://example.test?token=private") == nil)
    #expect(configuration(host: "https://user:password@example.test") == nil)
    #expect(configuration(token: "$(POSTHOG_PROJECT_TOKEN)") == nil)
    #expect(configuration(environment: "unknown") == nil)
    #expect(configuration(isDebug: true) != nil)
    #expect(configuration(isDebug: false, environment: "production") != nil)
    #expect(AnalyticsConfiguration.load(isDebug: false, arguments: ["-ui-testing-authenticated"]) == nil)
    #expect(AnalyticsConfiguration.load(isDebug: false, arguments: ["-overview-fixture", "design"]) == nil)
    #expect(AnalyticsConfiguration.load(isDebug: false, isTesting: true) == nil)
  }

  @Test func batchesContainOnlyAllowedPropertiesAndOpaqueIdentity() async throws {
    let fixture = makeFixture()
    defer { fixture.close() }
    fixture.analytics.setSession(accountID: "account-a", isActive: true, analyticsEnabled: true)
    fixture.analytics.capture(.appOpened)
    fixture.sdk.capture("app_opened", properties: [
      "title": "Private title", "email": "private@example.test", "search": "Private query",
      "url": "https://private.example.test", "record_id": "private-record",
      "$set": ["name": "Private name"], "platform": "wrong", "environment": "production",
    ])
    fixture.sdk.capture("unregistered_event", properties: ["note": "Private note"])
    fixture.sdk.capture("$exception", properties: ["$exception_message": "Private error"])
    fixture.sdk.flush()
    let batch = try await waitForBatch(token: fixture.token)
    let events = try #require(batch["batch"] as? [[String: Any]])
    #expect(events.filter { $0["event"] as? String == "app_opened" }.count == 2)
    #expect(events.allSatisfy { ["app_opened", "$identify"].contains($0["event"] as? String ?? "") })
    for event in events {
      #expect(event["distinct_id"] as? String == "account-a")
      let properties = try #require(event["properties"] as? [String: Any])
      let allowed: Set<String> = [
        "platform", "environment", "app_version", "$geoip_disable", "$lib", "$lib_version",
        "$session_id", "$is_identified", "$process_person_profile", "$anon_distinct_id",
      ]
      #expect(Set(properties.keys).isSubset(of: allowed))
      #expect(properties["platform"] as? String == "ios")
      #expect(properties["environment"] as? String == "preview")
      #expect(properties["$geoip_disable"] as? Bool == true)
    }
    #expect(AnalyticsWireProtocol.requests.allSatisfy { $0.url?.path == "/batch" })
    #expect(AnalyticsWireProtocol.requests.allSatisfy {
      $0.value(forHTTPHeaderField: AnalyticsRequestProtocol.gateHeader) == nil
    })
  }

  @Test func optOutStopsCaptureAndNetworkUntilReenabled() async throws {
    let fixture = makeFixture()
    defer { fixture.close() }
    fixture.analytics.setSession(accountID: "account-a", isActive: true, analyticsEnabled: true)
    fixture.analytics.capture(.appOpened)
    fixture.analytics.setSession(accountID: "account-a", isActive: true, analyticsEnabled: false)
    #expect(fixture.sdk.isOptOut())
    fixture.analytics.capture(.appOpened)
    fixture.sdk.capture("app_opened")
    fixture.analytics.setSession(accountID: "account-a", isActive: true, analyticsEnabled: true)
    #expect(!fixture.sdk.isOptOut())
    fixture.sdk.flush()
    let batch = try await waitForBatch(token: fixture.token)
    let events = try #require(batch["batch"] as? [[String: Any]])
    #expect(events.filter { $0["event"] as? String == "app_opened" }.count == 1)
    #expect(events.allSatisfy { $0["distinct_id"] as? String == "account-a" })
  }

  @Test func queuedEventsKeepTheirOriginalIdentityAcrossAccounts() async throws {
    let fixture = makeFixture()
    defer { fixture.close() }
    fixture.analytics.setSession(accountID: "account-a", isActive: true, analyticsEnabled: true)
    fixture.analytics.capture(.appOpened)
    fixture.analytics.setSession(accountID: "account-a", isActive: true, analyticsEnabled: false)
    fixture.analytics.setSession(accountID: nil, isActive: false, analyticsEnabled: nil)
    fixture.analytics.setSession(accountID: "account-b", isActive: true, analyticsEnabled: false)
    fixture.analytics.capture(.appOpened)
    #expect(fixture.sdk.isOptOut())
    fixture.analytics.setSession(accountID: "account-b", isActive: true, analyticsEnabled: true)
    fixture.analytics.capture(.appOpened)
    fixture.sdk.flush()
    let batch = try await waitForBatch(token: fixture.token)
    let events = try #require(batch["batch"] as? [[String: Any]])
    let actions = events.filter { $0["event"] as? String == "app_opened" }
    #expect(actions.map { $0["distinct_id"] as? String } == ["account-a", "account-b"])
    let anonymousIDs = events.filter { $0["event"] as? String == "$identify" }.compactMap {
      ($0["properties"] as? [String: Any])?["$anon_distinct_id"] as? String
    }
    #expect(anonymousIDs.count == 2)
    #expect(Set(anonymousIDs).count == 2)
    #expect(!anonymousIDs.contains("account-a"))
  }

  @Test func unknownConsentNeverInitializesOrIdentifiesTheSDK() {
    let fixture = makeFixture()
    defer { fixture.close() }
    fixture.analytics.setSession(accountID: "account-a", isActive: true, analyticsEnabled: nil)
    fixture.analytics.capture(.appOpened)
    #expect(fixture.sdk.isOptOut())
    #expect(AnalyticsWireProtocol.requests.isEmpty)
  }

  @Test func inactiveSessionDropsNewActionsUntilTheNextAccountIsReady() async throws {
    let fixture = makeFixture()
    defer { fixture.close() }
    fixture.analytics.setSession(accountID: "account-a", isActive: true, analyticsEnabled: true)
    fixture.analytics.capture(.appOpened)
    fixture.analytics.setSession(accountID: nil, isActive: false, analyticsEnabled: nil)
    fixture.analytics.capture(.appOpened)
    fixture.sdk.capture("app_opened")
    fixture.analytics.setSession(accountID: "account-a", isActive: false, analyticsEnabled: false)
    fixture.analytics.setSession(accountID: "account-a", isActive: false, analyticsEnabled: true)
    fixture.analytics.capture(.appOpened)
    fixture.analytics.setSession(accountID: "account-b", isActive: true, analyticsEnabled: true)
    fixture.analytics.capture(.appOpened)
    fixture.sdk.flush()
    let batch = try await waitForBatch(token: fixture.token)
    let events = try #require(batch["batch"] as? [[String: Any]])
    let actions = events.filter { $0["event"] as? String == "app_opened" }
    #expect(actions.map { $0["distinct_id"] as? String } == ["account-a", "account-b"])
  }

  @Test func appSessionTransitionsResetIdentityWithoutCountingRestorationAsLogin() async throws {
    let fixture = makeFixture()
    defer { fixture.close() }
    let store = KeychainSessionStore(service: "analytics.session.tests.\(UUID().uuidString)")
    defer { try? store.clear() }
    let client = PocketBaseClient(baseURL: URL(string: "https://example.test")!, sessionStore: store)
    let model = AppModel(client: client, sessionStore: store, themeStore: ThemeStore(), analytics: fixture.analytics)
    while model.phase == .restoring { await Task.yield() }
    model.phase = .signedIn(.preview)
    #expect(fixture.sdk.getDistinctId() != UserRecord.preview.id)
    model.replaceSignedInUser(.preview)
    #expect(fixture.sdk.getDistinctId() == UserRecord.preview.id)
    model.pauseAnalyticsUntilAccountRefresh()
    #expect(fixture.sdk.isOptOut())
    model.replaceSignedInUser(.preview)
    #expect(!fixture.sdk.isOptOut())
    model.setAnalyticsLocallyPaused(true, accountID: UserRecord.preview.id)
    #expect(fixture.sdk.isOptOut())
    model.replaceSignedInUser(.preview)
    #expect(fixture.sdk.isOptOut())
    model.setAnalyticsLocallyPaused(false, accountID: "another-account")
    #expect(fixture.sdk.isOptOut())
    model.setAnalyticsLocallyPaused(false, accountID: UserRecord.preview.id)
    #expect(!fixture.sdk.isOptOut())
    fixture.sdk.flush()
    let batch = try await waitForBatch(token: fixture.token)
    let events = try #require(batch["batch"] as? [[String: Any]])
    #expect(events.filter { $0["event"] as? String == "app_opened" }.count == 1)
    #expect(events.allSatisfy { ["app_opened", "$identify"].contains($0["event"] as? String ?? "") })
    #expect(events.filter { $0["event"] as? String == "$identify" }.count == 1)
    await model.expireSession()
    #expect(model.phase == .signedOut)
    #expect(fixture.sdk.isOptOut())
    #expect(fixture.sdk.getDistinctId() != UserRecord.preview.id)
  }

  @Test func networkGateRejectsAutomaticPathsAndOptedOutBatches() async throws {
    AnalyticsWireProtocol.reset()
    let underlying = URLSessionConfiguration.ephemeral
    underlying.protocolClasses = [AnalyticsWireProtocol.self]
    let gate = AnalyticsNetworkGate(host: URL(string: "https://analytics.example.test")!, sessionConfiguration: underlying)
    AnalyticsRequestProtocol.register(gate)
    defer { AnalyticsRequestProtocol.unregister(gate) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AnalyticsRequestProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    for path in ["/batch", "/flags", "/array/token/config", "/s/", "/i/v1/logs"] {
      var request = URLRequest(url: URL(string: "https://analytics.example.test\(path)")!)
      request.httpMethod = "POST"
      request.setValue(gate.id, forHTTPHeaderField: AnalyticsRequestProtocol.gateHeader)
      await #expect(throws: (any Error).self) { try await session.data(for: request) }
    }
    #expect(AnalyticsWireProtocol.requests.isEmpty)
    gate.setEnabled(true)
    for path in ["/flags", "/array/token/config", "/s/", "/i/v1/logs"] {
      var request = URLRequest(url: URL(string: "https://analytics.example.test\(path)")!)
      request.httpMethod = "POST"
      request.setValue(gate.id, forHTTPHeaderField: AnalyticsRequestProtocol.gateHeader)
      await #expect(throws: (any Error).self) { try await session.data(for: request) }
    }
    var allowed = URLRequest(url: URL(string: "https://analytics.example.test/batch")!)
    allowed.httpMethod = "POST"
    allowed.setValue(gate.id, forHTTPHeaderField: AnalyticsRequestProtocol.gateHeader)
    _ = try await session.data(for: allowed)
    #expect(AnalyticsWireProtocol.requests.count == 1)
  }

  private func configuration(
    token: String = "phc_test", host: String = "https://analytics.example.test",
    isDebug: Bool = true, environment: String = "preview"
  ) -> AnalyticsConfiguration? {
    AnalyticsConfiguration.parse(projectToken: token, host: host, environment: environment, appVersion: "0.1.0", isDebug: isDebug)
  }

  private func makeFixture() -> AnalyticsFixture {
    AnalyticsWireProtocol.reset()
    let token = "phc_test_\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: token)!
    let session = URLSessionConfiguration.ephemeral
    session.protocolClasses = [AnalyticsWireProtocol.self]
    let sdk = PostHogSDK.shared
    let analytics = NativeAnalytics(
      configuration: configuration(token: token), sdk: sdk,
      sessionConfiguration: session, compression: .none
    )
    return AnalyticsFixture(token: token, defaults: defaults, sdk: sdk, analytics: analytics)
  }

  private func waitForBatch(token: String) async throws -> [String: Any] {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
      for body in AnalyticsWireProtocol.bodies {
        if let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
          json["api_key"] as? String == token {
          return json
        }
      }
      await Task.yield()
    }
    Issue.record("The SDK did not deliver an isolated batch: \(AnalyticsWireProtocol.requests.count) requests, \(AnalyticsWireProtocol.bodies.count) bodies")
    return [:]
  }
}

@MainActor
private struct AnalyticsFixture {
  let token: String
  let defaults: UserDefaults
  let sdk: PostHogSDK
  let analytics: NativeAnalytics

  func close() {
    analytics.close()
    defaults.removePersistentDomain(forName: token)
  }
}

private final class AnalyticsWireProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var storedRequests: [URLRequest] = []
  nonisolated(unsafe) private static var storedBodies: [Data] = []
  static var requests: [URLRequest] { lock.withLock { storedRequests } }
  static var bodies: [Data] { lock.withLock { storedBodies } }

  static func reset() {
    lock.withLock { storedRequests = []; storedBodies = [] }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    var body = request.httpBody
    if let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var data = Data()
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
      }
      body = data
    }
    Self.lock.withLock {
      Self.storedRequests.append(request)
      if let body { Self.storedBodies.append(body) }
    }
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data("{}".utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
