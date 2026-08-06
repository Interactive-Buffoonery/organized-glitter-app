import Foundation
import Testing

@testable import OrganizedGlitter

@Suite(.serialized)
struct PocketBaseClientTests {
  @Test
  func registersAndRequestsVerificationWithoutAuthentication() async throws {
    PocketBaseClientURLProtocol.requests = []
    PocketBaseClientURLProtocol.requestBodies = []
    PocketBaseClientURLProtocol.responses = [
      (200, #"{"id":"user-1","email":"sarah@example.test","verified":false}"#),
      (204, ""),
    ]

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PocketBaseClientURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: KeychainSessionStore(
        service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"),
      urlSession: URLSession(configuration: configuration)
    )

    try await client.register(
      email: "sarah@example.test",
      username: "sarah",
      password: "password"
    )
    try await client.requestVerification(email: "sarah@example.test")

    #expect(
      PocketBaseClientURLProtocol.requests.map(\.url?.path) == [
        "/api/collections/users/records",
        "/api/collections/users/request-verification",
      ])
    #expect(
      PocketBaseClientURLProtocol.requests.allSatisfy {
        $0.value(forHTTPHeaderField: "Authorization") == nil
      })
    let body = try #require(
      JSONSerialization.jsonObject(with: PocketBaseClientURLProtocol.requestBodies[0])
        as? [String: Any])
    #expect(body["email"] as? String == "sarah@example.test")
    #expect(body["username"] as? String == "sarah")
    #expect(body["password"] as? String == "password")
    #expect(body["passwordConfirm"] as? String == "password")
    #expect(body["beta_tester"] as? Bool == true)
  }

  @Test
  func rejectsUnverifiedPasswordSessionBeforePersistingIt() async throws {
    PocketBaseClientURLProtocol.requests = []
    PocketBaseClientURLProtocol.requestBodies = []
    PocketBaseClientURLProtocol.responses = [
      (
        200,
        #"{"token":"token-1","record":{"id":"user-1","email":"sarah@example.test","verified":false}}"#
      )
    ]

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PocketBaseClientURLProtocol.self]
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    )
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration)
    )

    await #expect(throws: APIError.emailUnverified) {
      _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    }
    #expect(try store.load() == nil)
  }

  @Test
  func rejectsPasswordSessionWithoutVerificationStatus() async throws {
    PocketBaseClientURLProtocol.requests = []
    PocketBaseClientURLProtocol.requestBodies = []
    PocketBaseClientURLProtocol.responses = [
      (200, #"{"token":"token-1","record":{"id":"user-1"}}"#)
    ]

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PocketBaseClientURLProtocol.self]
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    )
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration)
    )

    await #expect(throws: APIError.emailUnverified) {
      _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    }
    #expect(try store.load() == nil)
  }

  @Test
  func requestsPasswordResetWithoutAuthentication() async throws {
    PocketBaseClientURLProtocol.requests = []
    PocketBaseClientURLProtocol.requestBodies = []
    PocketBaseClientURLProtocol.responses = [(204, "")]

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PocketBaseClientURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: KeychainSessionStore(
        service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"),
      urlSession: URLSession(configuration: configuration)
    )

    try await client.requestPasswordReset(email: "sarah@example.test")

    #expect(
      PocketBaseClientURLProtocol.requests.first?.url?.path
        == "/api/collections/users/request-password-reset")
    #expect(PocketBaseClientURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(
      try JSONSerialization.jsonObject(with: PocketBaseClientURLProtocol.requestBodies[0])
        as? [String: String] == ["email": "sarah@example.test"])
  }

  @Test
  func sendsAuthenticatedPartialUpdateAndDelete() async throws {
    PocketBaseClientURLProtocol.requests = []
    PocketBaseClientURLProtocol.requestBodies = []
    PocketBaseClientURLProtocol.responses = [
      (
        200,
        #"{"token":"token-1","record":{"id":"user-1","email":"sarah@example.test","verified":true}}"#
      ),
      (200, #"{"id":"project-1","title":"Updated"}"#),
      (204, ""),
    ]

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PocketBaseClientURLProtocol.self]
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    )
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration)
    )

    _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    let record: TestProject = try await client.update(
      collection: "projects",
      id: "project-1",
      body: TestProjectUpdate(title: "Updated")
    )
    try await client.delete(collection: "projects", id: "project-1")

    #expect(record == TestProject(id: "project-1", title: "Updated"))
    #expect(PocketBaseClientURLProtocol.requests.map(\.httpMethod) == ["POST", "PATCH", "DELETE"])
    #expect(
      PocketBaseClientURLProtocol.requests[1].value(forHTTPHeaderField: "Authorization")
        == "token-1"
    )
    #expect(
      try JSONDecoder().decode(
        TestProjectUpdate.self,
        from: PocketBaseClientURLProtocol.requestBodies[1]
      ) == TestProjectUpdate(title: "Updated")
    )

    await client.signOut()
  }

  @Test
  func refreshesOnceAndRetriesAnExpiredAuthenticatedRequest() async throws {
    PocketBaseClientURLProtocol.requests = []
    PocketBaseClientURLProtocol.requestBodies = []
    PocketBaseClientURLProtocol.responses = [
      (
        200,
        #"{"token":"token-1","record":{"id":"user-1","email":"sarah@example.test","verified":true}}"#
      ),
      (401, #"{"message":"Unauthenticated."}"#),
      (
        200,
        #"{"token":"token-2","record":{"id":"user-1","email":"sarah@example.test"}}"#
      ),
      (
        200,
        #"{"page":1,"perPage":50,"totalItems":0,"totalPages":0,"items":[]}"#
      ),
    ]

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PocketBaseClientURLProtocol.self]
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    )
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration)
    )

    _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    let records: RecordList<TestProject> = try await client.list(collection: "projects")

    #expect(records.items.isEmpty)
    #expect(
      PocketBaseClientURLProtocol.requests.map(\.url?.path) == [
        "/api/collections/users/auth-with-password",
        "/api/collections/projects/records",
        "/api/collections/users/auth-refresh",
        "/api/collections/projects/records",
      ])
    #expect(
      PocketBaseClientURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization")
        == "token-2"
    )
    #expect(
      PocketBaseClientURLProtocol.requests.allSatisfy {
        $0.cachePolicy == .reloadIgnoringLocalCacheData
      }
    )

    await client.signOut()
  }

  @Test
  func signOutKeepsAnInFlightRefreshFromRestoringKeychain() async throws {
    PocketBaseClientURLProtocol.requests = []
    PocketBaseClientURLProtocol.requestBodies = []
    PocketBaseClientURLProtocol.responses = [
      (
        200,
        #"{"token":"token-1","record":{"id":"user-1","email":"sarah@example.test","verified":true}}"#
      ),
      (
        200,
        #"{"token":"token-2","record":{"id":"user-1","email":"sarah@example.test"}}"#
      ),
    ]

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PocketBaseClientURLProtocol.self]
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    )
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration)
    )

    _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    PocketBaseClientURLProtocol.responseDelay = 0.1
    defer { PocketBaseClientURLProtocol.responseDelay = 0 }

    let refresh = Task {
      try await client.refreshAuthentication()
    }
    try await Task.sleep(for: .milliseconds(10))
    await client.signOut()
    _ = try? await refresh.value

    #expect(try store.load() == nil)
  }

  @MainActor
  @Test
  func loadsTheFirstServerFilteredLibraryPage() async throws {
    PocketBaseClientURLProtocol.requests = []
    PocketBaseClientURLProtocol.requestBodies = []
    PocketBaseClientURLProtocol.responses = [
      (
        200,
        #"{"token":"token-1","record":{"id":"user-1","email":"sarah@example.test","verified":true}}"#
      ),
      (
        200,
        #"{"page":1,"perPage":50,"totalItems":1,"totalPages":1,"items":[{"id":"project-1","title":"Moon Garden","user":"user-1","status":"progress","kit_category":"full","created":"2026-01-01 00:00:00.000Z","updated":"2026-01-02 00:00:00.000Z"}]}"#
      ),
    ]

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PocketBaseClientURLProtocol.self]
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    )
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: store,
      urlSession: URLSession(configuration: configuration)
    )

    _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    let model = LibraryModel(client: client, userID: "user-1")
    await model.load()

    #expect(model.projects.map(\.title) == ["Moon Garden"])
    let components = URLComponents(
      url: try #require(PocketBaseClientURLProtocol.requests.last?.url),
      resolvingAgainstBaseURL: false
    )
    #expect(components?.queryItems?.contains(URLQueryItem(name: "perPage", value: "50")) == true)
    #expect(
      components?.queryItems?.contains(
        URLQueryItem(name: "filter", value: #"user = "user-1""#)
      ) == true
    )
    #expect(
      components?.queryItems?.contains(
        URLQueryItem(name: "expand", value: "company,artist")
      ) == true
    )

    await client.signOut()
  }

  @Test
  func buildsFileURLsWithOptionalThumbAndPercentEncoding() throws {
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    )
    let client = PocketBaseClient(
      baseURL: URL(string: "http://127.0.0.1:8090")!,
      sessionStore: store
    )

    let url = client.fileURL(
      collection: "coloring_books",
      recordID: "rec1",
      filename: "cover.jpg"
    )
    #expect(url.absoluteString == "http://127.0.0.1:8090/api/files/coloring_books/rec1/cover.jpg")
    #expect(url.query() == nil)

    let thumbURL = client.fileURL(
      collection: "coloring_books",
      recordID: "rec1",
      filename: "cover.jpg",
      thumb: "320x420"
    )
    #expect(
      thumbURL.absoluteString
        == "http://127.0.0.1:8090/api/files/coloring_books/rec1/cover.jpg?thumb=320x420"
    )

    let encodedURL = client.fileURL(
      collection: "coloring_books",
      recordID: "rec1",
      filename: "cover image.jpg"
    )
    #expect(!encodedURL.absoluteString.contains(" "))
    #expect(encodedURL.absoluteString.hasSuffix("/cover%20image.jpg"))
  }

  @Test
  func seededBackendRoundTripsADisposableProject() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["RUN_SEEDED_POCKETBASE"] == "1" else {
      return
    }

    let identity = try #require(environment["SEEDED_PB_IDENTITY"])
    let password = try #require(environment["SEEDED_PB_PASSWORD"])
    let baseURL = try #require(
      URL(string: environment["SEEDED_PB_URL"] ?? "http://127.0.0.1:8090")
    )
    let store = KeychainSessionStore(
      service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"
    )
    let client = PocketBaseClient(baseURL: baseURL, sessionStore: store)
    let session = try await client.signIn(identity: identity, password: password)
    var createdID: String?

    do {
      let title = "Native integration \(UUID().uuidString)"
      let created: DiamondProjectRecord = try await client.create(
        collection: "projects",
        body: [
          "user": session.user.id,
          "title": title,
          "status": "wishlist",
          "kit_category": "full",
        ]
      )
      createdID = created.id
      #expect(created.title == title)

      let updated: DiamondProjectRecord = try await client.update(
        collection: "projects",
        id: created.id,
        body: ["title": "\(title) updated"]
      )
      #expect(updated.title.hasSuffix(" updated"))

      try await client.delete(collection: "projects", id: created.id)
      createdID = nil
    } catch {
      if let createdID {
        try? await client.delete(collection: "projects", id: createdID)
      }
      await client.signOut()
      throw error
    }

    await client.signOut()
  }
}

private struct TestProject: Decodable, Equatable {
  let id: String
  let title: String
}

private struct TestProjectUpdate: Codable, Equatable {
  let title: String
}

private final class PocketBaseClientURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var requests: [URLRequest] = []
  nonisolated(unsafe) static var requestBodies: [Data] = []
  nonisolated(unsafe) static var responses: [(Int, String)] = []
  nonisolated(unsafe) static var responseDelay: TimeInterval = 0

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    Self.requests.append(request)
    Self.requestBodies.append(bodyData)
    let (status, body) = Self.responses.removeFirst()
    if Self.responseDelay > 0 {
      Thread.sleep(forTimeInterval: Self.responseDelay)
    }

    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: status,
      httpVersion: nil,
      headerFields: nil
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private var bodyData: Data {
    if let body = request.httpBody {
      return body
    }
    guard let stream = request.httpBodyStream else {
      return Data()
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while true {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else {
        return data
      }
      data.append(buffer, count: count)
    }
  }
}
