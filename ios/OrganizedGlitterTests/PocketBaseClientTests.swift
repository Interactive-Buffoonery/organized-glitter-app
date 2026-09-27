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
  func sendsMultipartCreateAndUpdateRequests() async throws {
    PocketBaseClientURLProtocol.requests = []
    PocketBaseClientURLProtocol.requestBodies = []
    PocketBaseClientURLProtocol.responses = [
      (
        200,
        #"{"token":"token-1","record":{"id":"user-1","email":"sarah@example.test","verified":true}}"#
      ),
      (200, #"{"id":"note-1","title":"Created"}"#),
      (200, #"{"id":"page-1","title":"Updated"}"#),
    ]

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PocketBaseClientURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: KeychainSessionStore(
        service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"),
      urlSession: URLSession(configuration: configuration)
    )

    _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    let created: TestProject = try await client.create(
      collection: "progress_notes",
      multipart: PocketBaseMultipartForm(
        fields: ["project": "project-1", "date": "2026-09-19"],
        files: [
          PocketBaseMultipartFile(
            fieldName: "image",
            fileName: "note.png",
            contentType: "image/png",
            data: Data([0x01, 0x02])
          )
        ]
      )
    )
    let updated: TestProject = try await client.update(
      collection: "coloring_pages",
      id: "page-1",
      multipart: PocketBaseMultipartForm(
        files: [
          PocketBaseMultipartFile(
            fieldName: "photos+",
            fileName: "first.png",
            contentType: "image/png",
            data: Data([0x03])
          ),
          PocketBaseMultipartFile(
            fieldName: "photos+",
            fileName: "second.png",
            contentType: "image/png",
            data: Data([0x04])
          ),
        ]
      )
    )

    #expect(created == TestProject(id: "note-1", title: "Created"))
    #expect(updated == TestProject(id: "page-1", title: "Updated"))
    #expect(PocketBaseClientURLProtocol.requests.map(\.httpMethod) == ["POST", "POST", "PATCH"])
    let createContentType = try #require(
      PocketBaseClientURLProtocol.requests[1].value(forHTTPHeaderField: "Content-Type")
    )
    let updateContentType = try #require(
      PocketBaseClientURLProtocol.requests[2].value(forHTTPHeaderField: "Content-Type")
    )
    #expect(createContentType.hasPrefix("multipart/form-data; boundary="))
    #expect(updateContentType.hasPrefix("multipart/form-data; boundary="))
    #expect(
      String(decoding: PocketBaseClientURLProtocol.requestBodies[1], as: UTF8.self)
        .contains("name=\"image\"; filename=\"note.png\""))
    let updateBody = String(
      decoding: PocketBaseClientURLProtocol.requestBodies[2],
      as: UTF8.self
    )
    #expect(updateBody.components(separatedBy: "name=\"photos+\"").count - 1 == 2)

    await client.signOut()
  }

  @Test
  func replaysIdenticalMultipartBytesAfterAuthenticationRefresh() async throws {
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
      (200, #"{"id":"note-1","title":"Created"}"#),
    ]

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PocketBaseClientURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: KeychainSessionStore(
        service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"),
      urlSession: URLSession(configuration: configuration)
    )

    _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    let _: TestProject = try await client.create(
      collection: "progress_notes",
      multipart: PocketBaseMultipartForm(
        fields: ["project": "project-1", "date": "2026-09-19"],
        files: [
          PocketBaseMultipartFile(
            fieldName: "image",
            fileName: "note.png",
            contentType: "image/png",
            data: Data([0x01, 0x02, 0x03])
          )
        ]
      )
    )

    #expect(
      PocketBaseClientURLProtocol.requests.map(\.url?.path) == [
        "/api/collections/users/auth-with-password",
        "/api/collections/progress_notes/records",
        "/api/collections/users/auth-refresh",
        "/api/collections/progress_notes/records",
      ])
    #expect(
      PocketBaseClientURLProtocol.requests[3].value(forHTTPHeaderField: "Authorization")
        == "token-2"
    )
    #expect(
      PocketBaseClientURLProtocol.requests[1].value(forHTTPHeaderField: "Content-Type")
        == PocketBaseClientURLProtocol.requests[3].value(forHTTPHeaderField: "Content-Type")
    )
    #expect(
      PocketBaseClientURLProtocol.requestBodies[1]
        == PocketBaseClientURLProtocol.requestBodies[3]
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
    let records: RecordList<DiamondProjectRecord> = try await client.list(
      collection: "projects",
      perPage: 50,
      filter: PocketBaseFilter.equals(.user, "user-1"),
      sort: "-updated",
      expand: "company,artist"
    )

    #expect(records.items.map(\.title) == ["Moon Garden"])
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
      filename: "cover.jpg",
      token: "file-token"
    )
    #expect(
      url.absoluteString
        == "http://127.0.0.1:8090/api/files/coloring_books/rec1/cover.jpg?token=file-token")
    #expect(url.query() == "token=file-token")

    let thumbURL = client.fileURL(
      collection: "coloring_books",
      recordID: "rec1",
      filename: "cover.jpg",
      thumb: "320x420",
      token: "file-token"
    )
    #expect(
      thumbURL.absoluteString
        == "http://127.0.0.1:8090/api/files/coloring_books/rec1/cover.jpg?token=file-token&thumb=320x420"
    )

    let encodedURL = client.fileURL(
      collection: "coloring_books",
      recordID: "rec1",
      filename: "cover image.jpg",
      token: "file-token"
    )
    #expect(!encodedURL.absoluteString.contains(" "))
    #expect(encodedURL.absoluteString.contains("/cover%20image.jpg?token=file-token"))
  }

  @Test
  func requestsFileTokenWithCurrentAuthentication() async throws {
    PocketBaseClientURLProtocol.requests = []
    PocketBaseClientURLProtocol.requestBodies = []
    PocketBaseClientURLProtocol.responses = [
      (200, #"{"token":"auth-token","record":{"id":"user-1","verified":true}}"#),
      (200, #"{"token":"short-lived-file-token"}"#),
    ]

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PocketBaseClientURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: KeychainSessionStore(
        service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"),
      urlSession: URLSession(configuration: configuration)
    )

    _ = try await client.signIn(identity: "user", password: "password")
    #expect(try await client.fileToken() == "short-lived-file-token")
    #expect(PocketBaseClientURLProtocol.requests.last?.url?.path == "/api/files/token")
    #expect(PocketBaseClientURLProtocol.requests.last?.httpMethod == "POST")
    #expect(
      PocketBaseClientURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization")
        == "auth-token")
    await client.signOut()
  }

  @Test
  func seededBackendRoundTripsDisposableRecordsAndMultipartFiles() async throws {
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
    var projectID: String?
    var progressNoteID: String?
    var coloringBookID: String?

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
      projectID = created.id
      #expect(created.title == title)

      let updated: DiamondProjectRecord = try await client.update(
        collection: "projects",
        id: created.id,
        body: ["title": "\(title) updated"]
      )
      #expect(updated.title.hasSuffix(" updated"))

      let imageData = try #require(
        Data(
          base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )
      )
      let note: DiamondProgressNoteRecord = try await client.create(
        collection: "progress_notes",
        multipart: PocketBaseMultipartForm(
          fields: [
            "project": created.id,
            "date": "2026-09-19",
            "content": "Native integration note",
          ],
          files: [
            PocketBaseMultipartFile(
              fieldName: "image",
              fileName: "native-note.png",
              contentType: "image/png",
              data: imageData
            )
          ]
        )
      )
      progressNoteID = note.id
      #expect(note.project == created.id)
      #expect(note.image?.isEmpty == false)

      let book: ColoringBookRecord = try await client.create(
        collection: "coloring_books",
        body: SeededColoringBookCreate(
          user: session.user.id,
          title: "Native integration coloring \(UUID().uuidString)",
          status: "in_stash",
          totalPages: 1
        )
      )
      coloringBookID = book.id
      let pages: RecordList<ColoringPageRecord> = try await client.list(
        collection: "coloring_pages",
        perPage: 1,
        filter: #"book = "\#(book.id)""#,
        sort: "page_number"
      )
      let page = try #require(pages.items.first)
      #expect(page.pageNumber == 1)

      let firstUpload: ColoringPageRecord = try await client.update(
        collection: "coloring_pages",
        id: page.id,
        multipart: PocketBaseMultipartForm(
          files: [
            PocketBaseMultipartFile(
              fieldName: "photos+",
              fileName: "native-page-first.png",
              contentType: "image/png",
              data: imageData
            )
          ]
        )
      )
      let firstFilename = try #require(firstUpload.photos.first)

      let secondUpload: ColoringPageRecord = try await client.update(
        collection: "coloring_pages",
        id: page.id,
        multipart: PocketBaseMultipartForm(
          files: [
            PocketBaseMultipartFile(
              fieldName: "photos+",
              fileName: "native-page-second.png",
              contentType: "image/png",
              data: imageData
            )
          ]
        )
      )
      #expect(secondUpload.photos.count == 2)
      #expect(secondUpload.photos.contains(firstFilename))

      let refetchedPage: ColoringPageRecord = try await client.get(
        collection: "coloring_pages",
        id: page.id
      )
      #expect(refetchedPage.photos.count == 2)
      #expect(refetchedPage.photos.contains(firstFilename))

      try await client.delete(collection: "progress_notes", id: note.id)
      progressNoteID = nil
      try await client.delete(collection: "projects", id: created.id)
      projectID = nil
      try await client.delete(collection: "coloring_books", id: book.id)
      coloringBookID = nil
    } catch {
      if let progressNoteID {
        try? await client.delete(collection: "progress_notes", id: progressNoteID)
      }
      if let projectID {
        try? await client.delete(collection: "projects", id: projectID)
      }
      if let coloringBookID {
        try? await client.delete(collection: "coloring_books", id: coloringBookID)
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

private struct SeededColoringBookCreate: Encodable {
  let user: String
  let title: String
  let status: String
  let totalPages: Int

  enum CodingKeys: String, CodingKey {
    case user, title, status
    case totalPages = "total_pages"
  }
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
