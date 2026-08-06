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
        == [.books, .pages])
    #expect(
      LibrarySection.available(
        for: VerticalPreferences(diamondPainting: true, coloringBooks: true))
        == [.diamonds, .books, .pages])
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

  private func makeClient(responses: [(Int, String)] = []) -> PocketBaseClient {
    AccountPreferencesURLProtocol.requests = []
    AccountPreferencesURLProtocol.requestBodies = []
    AccountPreferencesURLProtocol.responses = responses
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

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.requests.append(request)
    Self.requestBodies.append(bodyData)
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
