import Foundation
import Testing

@testable import OrganizedGlitter

@MainActor
@Suite(.serialized)
struct EntryOnlineWriteTests {
  @Test(arguments: ["tags", "image", "cover_image", "total_pages"])
  func onlineFieldsRejectEntireQueuedPatch(field: String) async throws {
    let library = try localFeatureLibrary()
    let book = featureBook("book", title: "Original")
    try await library.store.ingest(.book(book), scope: library.scope)
    await #expect(throws: LocalLibraryError.unsupportedField) {
      _ = try await library.store.queueEdit(
        scope: library.scope, key: LibraryItem.book(book).localRecordKey,
        patch: ["title": .string("Changed"), field: .string("")])
    }
    #expect(try await library.store.pendingCount(scope: library.scope) == 0)
    let entry = try #require(await library.store.entry(
      scope: library.scope, key: LibraryItem.book(book).localRecordKey))
    #expect(entry.item.title == "Original")
  }

  @Test(arguments: ["tags", "image"])
  func projectOnlineFieldsRejectQueuedEdits(field: String) async throws {
    let library = try localFeatureLibrary()
    let project = featureProject("project", title: "Original")
    try await library.store.ingest(.diamond(project), scope: library.scope)
    await #expect(throws: LocalLibraryError.unsupportedField) {
      _ = try await library.store.queueEdit(
        scope: library.scope, key: LibraryItem.diamond(project).localRecordKey,
        patch: [field: .string("")])
    }
    #expect(try await library.store.pendingCount(scope: library.scope) == 0)
  }

  @Test func unchangedTagsMakeNoRequest() async throws {
    let library = try localFeatureLibrary()
    try await TagLinks.sync(
      kind: .diamondTag, recordID: "project", from: ["tag"], to: ["tag"], library: library)
  }

  @Test(arguments: [ListKind.diamondTag, .coloringTag])
  func tagSyncCreatesOnlyMissingLinks(kind: ListKind) async throws {
    let library = try await makeLibrary()
    defer { library.pauseWrites() }
    EntryWriteProtocol.links = #"[{"id":"existing","tag":"kept"},{"id":"already-added","tag":"added"}]"#
    try await TagLinks.sync(
      kind: kind, recordID: "parent", from: ["kept"], to: ["kept", "added", "missing"],
      library: library)
    let writes = EntryWriteProtocol.writes
    #expect(writes.map(\.request.httpMethod) == ["POST"])
    let body = try #require(JSONSerialization.jsonObject(with: writes[0].body) as? [String: String])
    #expect(body == [kind == .diamondTag ? "project" : "book": "parent", "tag": "missing"])
  }

  @Test func failedTagSaveRetriesWithoutDuplicatingAcceptedLink() async throws {
    let library = try await makeLibrary()
    defer { library.pauseWrites() }
    EntryWriteProtocol.failWrite = true
    await #expect(throws: APIError.server) {
      try await TagLinks.sync(
        kind: .diamondTag, recordID: "parent", from: [], to: ["added"], library: library)
    }
    EntryWriteProtocol.failWrite = false
    EntryWriteProtocol.links = #"[{"id":"accepted-link","tag":"added"}]"#
    try await TagLinks.sync(
      kind: .diamondTag, recordID: "parent", from: [], to: ["added"], library: library)
    #expect(EntryWriteProtocol.writes.count == 1)
  }

  @Test func cancelledTaskRejectsCoverSaveBeforeRequest() async throws {
    let library = try await makeLibrary()
    defer { library.pauseWrites() }
    let task = Task { try await apply(.remove, library: library) }
    task.cancel()
    await #expect(throws: APIError.cancelled) { try await task.value }
    #expect(EntryWriteProtocol.writes.isEmpty)
  }

  @Test func tagSyncDeletesOnlyRemovedLinks() async throws {
    let library = try await makeLibrary()
    defer { library.pauseWrites() }
    EntryWriteProtocol.links = #"[{"id":"kept-link","tag":"kept"},{"id":"removed-link","tag":"removed"}]"#
    try await TagLinks.sync(
      kind: .diamondTag, recordID: "parent", from: ["kept", "removed"], to: ["kept"],
      library: library)
    #expect(EntryWriteProtocol.writes.map(\.request.httpMethod) == ["DELETE"])
    #expect(EntryWriteProtocol.writes.first?.request.url?.lastPathComponent == "removed-link")
  }

  @Test func unchangedCoverReturnsCachedRecordWithoutRequest() async throws {
    let library = try localFeatureLibrary()
    let book = featureBook("book", title: "Original")
    try await library.store.ingest(.book(book), scope: library.scope)
    try await library.loadLocal()
    let saved: ColoringBookRecord = try await CoverUpload.apply(
      .unchanged, collection: "coloring_books", recordID: book.id,
      field: "cover_image", library: library)
    #expect(saved == book)
  }

  @Test func coverRemovalSendsOnlyEmptyCoverField() async throws {
    let library = try await makeLibrary()
    defer { library.pauseWrites() }
    let _: ColoringBookRecord = try await apply(.remove, library: library)
    let write = try #require(EntryWriteProtocol.writes.first)
    #expect(write.request.httpMethod == "PATCH")
    #expect(try JSONSerialization.jsonObject(with: write.body) as? [String: String] == ["cover_image": ""])
  }

  @Test func coverReplacementSendsMultipartFile() async throws {
    let library = try await makeLibrary()
    defer { library.pauseWrites() }
    let photo = ProcessedDetailPhoto(data: Data("photo-bytes".utf8), fileName: "cover.jpg", contentType: "image/jpeg")
    let _: ColoringBookRecord = try await apply(.replace(photo), library: library)
    let write = try #require(EntryWriteProtocol.writes.first)
    #expect(write.request.httpMethod == "PATCH")
    #expect(write.request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
    let body = String(decoding: write.body, as: UTF8.self)
    #expect(body.contains("name=\"cover_image\"; filename=\"cover.jpg\""))
    #expect(body.contains("Content-Type: image/jpeg"))
    #expect(body.contains("photo-bytes"))
  }

  @Test func failedCoverSaveCanRetryWithoutChangingCachedRecord() async throws {
    let library = try await makeLibrary()
    defer { library.pauseWrites() }
    EntryWriteProtocol.failWrite = true
    await #expect(throws: APIError.server) { try await apply(.remove, library: library) }
    let cached: ColoringBookRecord = try library.record(collection: "coloring_books", id: "book")
    #expect(cached.title == "Original")
    EntryWriteProtocol.failWrite = false
    let saved = try await apply(.remove, library: library)
    #expect(saved.id == "book")
    #expect(EntryWriteProtocol.writes.count == 2)
    #expect(EntryWriteProtocol.writes[0].body == EntryWriteProtocol.writes[1].body)
  }

  @Test func pausedSessionCancelsCoverSaveBeforeRequest() async throws {
    let library = try await makeLibrary()
    library.pauseWrites()
    await #expect(throws: APIError.cancelled) { try await apply(.remove, library: library) }
    #expect(EntryWriteProtocol.writes.isEmpty)
  }

  private func apply(_ change: CoverChange, library: LibrarySession) async throws -> ColoringBookRecord {
    try await CoverUpload.apply(change, collection: "coloring_books", recordID: "book", field: "cover_image", library: library)
  }

  private func makeLibrary() async throws -> LibrarySession {
    EntryWriteProtocol.writes = []
    EntryWriteProtocol.links = "[]"
    EntryWriteProtocol.failWrite = false
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [EntryWriteProtocol.self]
    let keychain = KeychainSessionStore(service: "EntryWriteTests.\(UUID().uuidString)")
    let client = PocketBaseClient(
      baseURL: URL(string: "https://entry.example.test")!, sessionStore: keychain,
      urlSession: URLSession(configuration: configuration))
    _ = try await client.signIn(identity: "example", password: "example")
    try keychain.clear()
    let library = LibrarySession(client: client, userID: "feature-user", store: try LocalLibraryStore.inMemory())
    try await library.store.ingest(.book(featureBook("book", title: "Original")), scope: library.scope)
    try await library.loadLocal()
    return library
  }
}

// Follows the existing PocketBaseClientURLProtocol body-stream stub pattern.
private final class EntryWriteProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var writes: [(request: URLRequest, body: Data)] = []
  nonisolated(unsafe) static var links = "[]"
  nonisolated(unsafe) static var failWrite = false

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  override func startLoading() {
    let path = request.url!.path
    let method = request.httpMethod ?? "GET"
    let status: Int
    let body: String
    if path.hasSuffix("auth-with-password") {
      status = 200
      body = #"{"token":"example-token","record":{"id":"feature-user","verified":true}}"#
    } else if path.contains("/records") {
      if method == "GET" {
        status = 200
        body = "{\"page\":1,\"perPage\":200,\"totalPages\":1,\"totalItems\":2,\"items\":\(Self.links)}"
      } else {
        Self.writes.append((request, bodyData))
        status = Self.failWrite ? 500 : (method == "DELETE" ? 204 : 200)
        body = path.contains("coloring_books")
          ? String(decoding: try! JSONEncoder().encode(featureBook("book", title: "Original")), as: UTF8.self)
          : #"{"id":"new-link","tag":"missing"}"#
      }
    } else {
      status = 200
      let book = String(decoding: try! JSONEncoder().encode(featureBook("book", title: "Original")), as: UTF8.self)
      body = "{\"version\":1,\"projects\":[],\"coloringBooks\":[\(book)],\"coloringPages\":[],\"progressNotes\":[],\"coloringPageProgressNotes\":[]}"
    }
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  private var bodyData: Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while true {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { return data }
      data.append(buffer, count: count)
    }
  }
}
