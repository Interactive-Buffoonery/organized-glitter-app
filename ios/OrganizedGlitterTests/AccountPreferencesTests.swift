import Foundation
import Testing

@testable import OrganizedGlitter

@MainActor
@Suite(.serialized)
struct AccountPreferencesTests {
  @Test
  func enabledCraftsChooseLibrarySections() {
    #expect(
      LibrarySection.available(
        for: VerticalPreferences(diamondPainting: true, coloringBooks: false))
        == [.diamonds])
    #expect(
      LibrarySection.available(
        for: VerticalPreferences(diamondPainting: false, coloringBooks: true))
        == [.books])
    #expect(
      LibrarySection.available(
        for: VerticalPreferences(diamondPainting: true, coloringBooks: true))
        == [.diamonds, .books])
  }

  @Test
  func rejectsDisablingBothCraftsWithoutWriting() async throws {
    let client = makeClient()
    let model = AccountPreferencesModel(client: client, user: .preview)

    let saved = await model.updateVerticals(
      VerticalPreferences(diamondPainting: false, coloringBooks: false))

    #expect(!saved)
    #expect(model.errorMessage == "Keep at least one craft enabled.")
    #expect(AccountPreferencesURLProtocol.requests.isEmpty)
  }

  @Test
  func writesOnlyUsernameThenRefreshesTheUser() async throws {
    let client = makeClient(
      responses: [
        (200, #"{"token":"token","record":{"id":"preview-user","verified":true}}"#),
        (200, #"{"id":"preview-user","username":"New name"}"#),
        (200, #"{"id":"preview-user","username":"New name","timezone":"America/New_York"}"#),
      ])
    _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    let model = AccountPreferencesModel(client: client, user: .preview)

    #expect(await model.updateProfile(username: "  New name  "))
    #expect(model.user.username == "New name")
    #expect(model.user.timezone == "America/New_York")
    #expect(AccountPreferencesURLProtocol.requests.map(\.httpMethod) == ["POST", "PATCH", "GET"])
    #expect(
      try JSONSerialization.jsonObject(with: AccountPreferencesURLProtocol.requestBodies[1])
        as? [String: String] == ["username": "New name"])
  }

  @Test
  func writesOnlyAnalyticsOptOutThenRefreshesTheUser() async throws {
    let client = makeClient(
      responses: [
        (200, #"{"token":"token","record":{"id":"preview-user","verified":true}}"#),
        (200, #"{"id":"preview-user","analytics_opt_out":true}"#),
        (200, #"{"id":"preview-user","analytics_opt_out":true}"#),
      ])
    _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    let model = AccountPreferencesModel(client: client, user: .preview)

    #expect(await model.updateAnalyticsEnabled(false))
    #expect(model.user.analyticsOptOut == true)
    #expect(AccountPreferencesURLProtocol.requests.map(\.httpMethod) == ["POST", "PATCH", "GET"])
    #expect(
      try JSONSerialization.jsonObject(with: AccountPreferencesURLProtocol.requestBodies[1])
        as? [String: Bool] == ["analytics_opt_out": true])
  }

  @Test
  func lostAnalyticsWriteResponseReloadsAndAcceptsTheServerChoice() async throws {
    let client = makeClient(
      responses: [
        (200, #"{"token":"token","record":{"id":"preview-user","verified":true}}"#),
        (503, #"{}"#),
        (200, #"{"id":"preview-user","analytics_opt_out":true}"#),
      ])
    _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    var paused = false
    var refreshed: UserRecord?
    let model = AccountPreferencesModel(
      client: client,
      user: .preview,
      onUserRefresh: { refreshed = $0 },
      onAnalyticsConsentUnknown: { paused = true })

    #expect(await model.updateAnalyticsEnabled(false))
    #expect(paused)
    #expect(refreshed?.analyticsOptOut == true)
    #expect(model.user.analyticsOptOut == true)
    #expect(model.errorMessage == nil)
    #expect(AccountPreferencesURLProtocol.requests.map(\.httpMethod) == ["POST", "PATCH", "GET"])
  }


  @Test
  func analyticsWriteWithoutTheFieldDoesNotClaimSuccess() async throws {
    let client = makeClient(
      responses: [
        (200, #"{"token":"token","record":{"id":"preview-user","verified":true}}"#),
        (200, #"{"id":"preview-user"}"#),
        (200, #"{"id":"preview-user"}"#),
      ])
    _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    var paused = false
    let model = AccountPreferencesModel(
      client: client,
      user: .preview,
      onAnalyticsConsentUnknown: { paused = true })

    #expect(!(await model.updateAnalyticsEnabled(false)))
    #expect(paused)
    #expect(model.user.analyticsOptOut == nil)
  }

  @Test
  func analyticsRefreshDoesNotOverlapAWrite() async throws {
    let client = makeClient(
      responses: [
        (200, #"{"token":"token","record":{"id":"preview-user","verified":true}}"#),
        (200, #"{"id":"preview-user","analytics_opt_out":false}"#),
      ])
    _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    AccountPreferencesURLProtocol.responseDelay = 0.1
    let model = AccountPreferencesModel(client: client, user: .preview)

    let refresh = Task { await model.refreshAnalyticsPreference() }
    while AccountPreferencesURLProtocol.requests.count < 2 { await Task.yield() }
    #expect(!(await model.updateAnalyticsEnabled(false)))
    await refresh.value

    #expect(AccountPreferencesURLProtocol.requests.map(\.httpMethod) == ["POST", "GET"])
    #expect(model.user.analyticsOptOut == false)
  }

  @Test
  func accountLoadAppliesUserBeforeUnrelatedSettingsFailure() async throws {
    let client = makeClient(
      responses: [
        (200, #"{"token":"token","record":{"id":"preview-user","verified":true}}"#),
        (200, #"{"id":"preview-user","analytics_opt_out":true}"#),
        (503, #"{}"#),
      ])
    _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    var refreshed: UserRecord?
    let model = AccountPreferencesModel(
      client: client, user: .preview, onUserRefresh: { refreshed = $0 })

    await model.load()

    #expect(refreshed?.analyticsOptOut == true)
    #expect(model.user.analyticsOptOut == true)
    #expect(model.errorMessage != nil)
  }

  @Test
  func successfulAnalyticsRefreshClearsOnlyItsPreviousError() async throws {
    let client = makeClient(
      responses: [
        (200, #"{"token":"token","record":{"id":"preview-user","verified":true}}"#),
        (503, #"{}"#),
        (503, #"{}"#),
        (200, #"{"id":"preview-user","analytics_opt_out":false}"#),
      ])
    _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    let model = AccountPreferencesModel(client: client, user: .preview)

    #expect(!(await model.updateAnalyticsEnabled(false)))
    #expect(model.errorMessage == "The analytics choice could not be confirmed. Analytics will stay off until your account reloads.")
    await model.refreshAnalyticsPreference()

    #expect(model.errorMessage == nil)
    #expect(model.user.analyticsOptOut == false)
  }

  @Test
  func unconfirmedAnalyticsWriteStaysPausedWhenReloadAlsoFails() async throws {
    let client = makeClient(
      responses: [
        (200, #"{"token":"token","record":{"id":"preview-user","verified":true}}"#),
        (503, #"{}"#),
        (503, #"{}"#),
      ])
    _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    var paused = false
    var refreshed = false
    let model = AccountPreferencesModel(
      client: client,
      user: .preview,
      onUserRefresh: { _ in refreshed = true },
      onAnalyticsConsentUnknown: { paused = true })

    #expect(!(await model.updateAnalyticsEnabled(false)))
    #expect(paused)
    #expect(!refreshed)
    #expect(model.errorMessage == "The analytics choice could not be confirmed. Analytics will stay off until your account reloads.")
  }

  @Test
  func createsThenPartiallyUpdatesVerticalSettingsAndRefreshes() async throws {
    let client = makeClient(
      responses: [
        (200, #"{"token":"token","record":{"id":"preview-user","verified":true}}"#),
        (
          200,
          #"{"id":"settings-1","vertical_enabled":{"diamond_painting":true,"coloring_books":true}}"#
        ),
        (
          200,
          #"{"page":1,"perPage":1,"totalItems":1,"totalPages":1,"items":[{"id":"settings-1","vertical_enabled":{"diamond_painting":true,"coloring_books":true}}]}"#
        ),
        (
          200,
          #"{"id":"settings-1","vertical_enabled":{"diamond_painting":false,"coloring_books":true}}"#
        ),
        (
          200,
          #"{"page":1,"perPage":1,"totalItems":1,"totalPages":1,"items":[{"id":"settings-1","vertical_enabled":{"diamond_painting":false,"coloring_books":true}}]}"#
        ),
      ])
    _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    let model = AccountPreferencesModel(client: client, user: .preview)

    #expect(
      await model.updateVerticals(
        VerticalPreferences(diamondPainting: true, coloringBooks: true)))
    #expect(
      await model.updateVerticals(
        VerticalPreferences(diamondPainting: false, coloringBooks: true)))

    #expect(
      AccountPreferencesURLProtocol.requests.map(\.httpMethod)
        == ["POST", "POST", "GET", "PATCH", "GET"])
    let updateBody = try #require(
      JSONSerialization.jsonObject(with: AccountPreferencesURLProtocol.requestBodies[3])
        as? [String: Any])
    #expect(updateBody.keys.sorted() == ["vertical_enabled"])
    #expect(model.verticals == VerticalPreferences(diamondPainting: false, coloringBooks: true))
  }

  @Test
  func localPauseDoesNotWriteOrChangeTheAccountChoice() {
    let client = makeClient()
    var paused = false
    let model = AccountPreferencesModel(
      client: client, user: .preview,
      onAnalyticsLocalPauseChanged: { paused = $0 })

    model.pauseAnalyticsLocally()

    #expect(paused)
    #expect(model.isAnalyticsLocallyPaused)
    #expect(model.user.analyticsOptOut == false)
    #expect(AccountPreferencesURLProtocol.requests.isEmpty)
  }

  @Test
  func refreshPreservesLocalPauseAndConfirmedSaveClearsIt() async throws {
    let client = makeClient(responses: [
      (200, #"{"token":"token","record":{"id":"preview-user","verified":true}}"#),
      (200, #"{"id":"preview-user","analytics_opt_out":false}"#),
      (200, #"{"id":"preview-user","analytics_opt_out":false}"#),
      (200, #"{"id":"preview-user","analytics_opt_out":false}"#),
    ])
    _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    var pauses: [Bool] = []
    let model = AccountPreferencesModel(
      client: client, user: .preview,
      onAnalyticsLocalPauseChanged: { pauses.append($0) })
    model.pauseAnalyticsLocally()
    await model.refreshAnalyticsPreference()
    #expect(model.isAnalyticsLocallyPaused)
    #expect(pauses == [true])

    #expect(await model.updateAnalyticsEnabled(true))
    #expect(!model.isAnalyticsLocallyPaused)
    #expect(pauses == [true, false])
  }

  @Test
  func failedAnalyticsSaveCannotClearLocalPause() async throws {
    let client = makeClient(responses: [
      (200, #"{"token":"token","record":{"id":"preview-user","verified":true}}"#),
      (503, #"{}"#),
      (200, #"{"id":"preview-user","analytics_opt_out":false}"#),
    ])
    _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    var pauses: [Bool] = []
    let model = AccountPreferencesModel(
      client: client, user: .preview,
      onAnalyticsLocalPauseChanged: { pauses.append($0) })
    model.pauseAnalyticsLocally()
    #expect(!(await model.updateAnalyticsEnabled(false)))
    #expect(model.isAnalyticsLocallyPaused)
    #expect(pauses == [true])
  }

  @Test
  func localPauseDuringSaveWinsOverTheOlderSave() async throws {
    let client = makeClient(responses: [
      (200, #"{"token":"token","record":{"id":"preview-user","verified":true}}"#),
      (200, #"{"id":"preview-user","analytics_opt_out":false}"#),
      (200, #"{"id":"preview-user","analytics_opt_out":false}"#),
    ])
    _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    AccountPreferencesURLProtocol.responseDelay = 0.1
    let model = AccountPreferencesModel(client: client, user: .preview)
    let save = Task { await model.updateAnalyticsEnabled(true) }
    while AccountPreferencesURLProtocol.requests.count < 2 { await Task.yield() }
    model.pauseAnalyticsLocally()
    #expect(await save.value)
    #expect(model.isAnalyticsLocallyPaused)
  }

  private func makeClient(responses: [(Int, String)] = []) -> PocketBaseClient {
    AccountPreferencesURLProtocol.requests = []
    AccountPreferencesURLProtocol.requestBodies = []
    AccountPreferencesURLProtocol.responses = responses
    AccountPreferencesURLProtocol.responseDelay = 0
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AccountPreferencesURLProtocol.self]
    return PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: KeychainSessionStore(
        service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"),
      urlSession: URLSession(configuration: configuration)
    )
  }
}

private final class AccountPreferencesURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var requests: [URLRequest] = []
  nonisolated(unsafe) static var requestBodies: [Data] = []
  nonisolated(unsafe) static var responses: [(Int, String)] = []
  nonisolated(unsafe) static var responseDelay: TimeInterval = 0

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.requests.append(request)
    Self.requestBodies.append(bodyData)
    if Self.responseDelay > 0 { Thread.sleep(forTimeInterval: Self.responseDelay) }
    let (status, body) = Self.responses.removeFirst()
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
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
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { break }
      data.append(buffer, count: count)
    }
    return data
  }
}
