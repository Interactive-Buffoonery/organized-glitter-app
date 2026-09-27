import Foundation
import Testing

@testable import OrganizedGlitter

@MainActor
@Suite(.serialized)
struct LibraryItemDetailModelTests {
  @Test func statusFeedbackFollowsCommittedChanges() async throws {
    let library = try localFeatureLibrary()
    let project = featureProject("project", title: "Moon Garden")
    try await library.store.ingest(.diamond(project), scope: library.scope)
    let model = LibraryItemDetailModel(item: .diamond(project), library: library)
    #expect(model.statusSaveRevision == 0)
    #expect(!(await model.setStatus("wishlist")))
    #expect(model.statusSaveRevision == 0)
    #expect(await model.setStatus("progress"))
    #expect(model.statusSaveRevision == 1)
    #expect(model.item.status == "progress")
    #expect(!(await model.setStatus("progress")))
    #expect(model.statusSaveRevision == 1)
    #expect(await model.setStatus("completed"))
    #expect(model.statusSaveRevision == 2)
    try await library.close(removingData: false)
    #expect(!(await model.setStatus("stash")))
    #expect(model.statusSaveRevision == 2)
    #expect(model.item.status == "completed")
  }

  @Test func bookStatusAlsoConfirmsCommittedChanges() async throws {
    let library = try localFeatureLibrary()
    let book = featureBook("book", title: "Quiet Pages")
    try await library.store.ingest(.book(book), scope: library.scope)
    let model = LibraryItemDetailModel(item: .book(book), library: library)
    #expect(await model.setStatus("completed"))
    #expect(model.statusSaveRevision == 1)
    #expect(model.item.status == "completed")
    try await library.close(removingData: false)
  }

  @Test(arguments: [false, true])
  func statusFeedbackRepeatsAfterEditorSave(isBook: Bool) async throws {
    let library = try localFeatureLibrary()
    let item: LibraryItem = isBook
      ? .book(featureBook("book", title: "Quiet Pages"))
      : .diamond(featureProject("project", title: "Moon Garden"))
    try await library.store.ingest(item, scope: library.scope)
    let model = LibraryItemDetailModel(item: item, library: library)
    #expect(await model.setStatus("completed"))
    #expect(model.statusSaveRevision == 1)

    let saved: LibraryItem
    if isBook {
      saved = .book(try await library.update(
        collection: "coloring_books", id: "book", body: ["status": "purchased"]))
    } else {
      saved = .diamond(try await library.update(
        collection: "projects", id: "project", body: ["status": "progress"]))
    }
    await model.acceptSaved(saved)
    #expect(model.statusSaveRevision == 1)
    #expect(await model.setStatus("completed"))
    #expect(model.statusSaveRevision == 2)
    #expect(model.item.status == "completed")
    try await library.close(removingData: false)
  }

  @Test func lostNoteResponseNeedsAuthoritativeRefreshBeforeRetry() async throws {
    LostNoteURLProtocol.snapshotAvailable = false
    LostNoteURLProtocol.createRequests = 0
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LostNoteURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://lost-note.example.test")!,
      sessionStore: KeychainSessionStore(service: "LostNoteTests.\(UUID().uuidString)"),
      urlSession: URLSession(configuration: configuration))
    await client.prepareOfflineSession(StoredSession(token: "example-token", userID: "feature-user"))
    let library = LibrarySession(
      client: client, userID: "feature-user", store: try LocalLibraryStore.inMemory())
    let project = featureProject("project", title: "Moon Garden")
    try await library.store.ingest(.diamond(project), scope: library.scope)
    let model = LibraryItemDetailModel(item: .diamond(project), library: library)
    #expect(await model.load())

    let saved = await model.addDiamondProgressNote(
      content: "Half finished", date: Date(timeIntervalSince1970: 0), photo: nil)
    #expect(!saved)
    #expect(model.unresolvedWriteState == .needsRefresh)
    #expect(model.progressNotes.isEmpty)
    #expect(LostNoteURLProtocol.createRequests == 1)
    let duplicate = await model.addDiamondProgressNote(
      content: "Half finished", date: Date(timeIntervalSince1970: 0), photo: nil)
    #expect(!duplicate)
    #expect(LostNoteURLProtocol.createRequests == 1)

    LostNoteURLProtocol.snapshotAvailable = true
    #expect(await model.refreshUnresolvedWriteStatus())
    #expect(model.unresolvedWriteState == .refreshed)
    #expect(model.progressNotes.map(\.id) == ["saved-note"])
    #expect(model.lastAddedProgressNoteID == nil)
  }

  @Test func confirmedNoteIsTheOneToReveal() async throws {
    LostNoteURLProtocol.createSucceeds = true
    defer { LostNoteURLProtocol.createSucceeds = false }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LostNoteURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://saved-note.example.test")!,
      sessionStore: KeychainSessionStore(service: "SavedNoteTests.\(UUID().uuidString)"),
      urlSession: URLSession(configuration: configuration))
    await client.prepareOfflineSession(StoredSession(token: "example-token", userID: "feature-user"))
    let library = LibrarySession(
      client: client, userID: "feature-user", store: try LocalLibraryStore.inMemory())
    let project = featureProject("project", title: "Moon Garden")
    try await library.store.ingest(.diamond(project), scope: library.scope)
    let model = LibraryItemDetailModel(item: .diamond(project), library: library)
    #expect(await model.load())
    #expect(model.lastAddedProgressNoteID == nil)

    #expect(
      await model.addDiamondProgressNote(
        content: "Half finished", date: Date(timeIntervalSince1970: 0), photo: nil))
    #expect(model.lastAddedProgressNoteID == "created-note")
    #expect(model.progressNotes.map(\.id) == ["created-note"])
  }

  @Test func bookPagesFilterAndPaginateFromLocalLibrary() async throws {
    let library = try localFeatureLibrary()
    let book = featureBook("book", title: "Quiet Pages")
    try await library.store.ingest(.book(book), scope: library.scope)
    for number in 1...30 {
      try await library.store.ingest(
        .page(featurePage("page-\(number)", book: book.id, number: number,
          status: number.isMultiple(of: 2) ? "completed" : "in_progress")),
        scope: library.scope)
    }
    let model = LibraryItemDetailModel(item: .book(book), library: library)
    #expect(await model.load())
    #expect(model.bookPages.count == 24)
    #expect(model.canLoadMoreBookPages)
    await model.loadMoreBookPages()
    #expect(model.bookPages.count == 30)
    await model.setBookPageFilter(.completed)
    #expect(model.bookPages.count == 15)
    #expect(model.bookPages.allSatisfy { $0.status == "completed" })
  }

  @Test func detailLoadsCurrentLocalRecordAfterUpdate() async throws {
    let library = try localFeatureLibrary()
    let initial = featureProject("project", title: "First", status: "wishlist")
    try await library.store.ingest(.diamond(initial), scope: library.scope)
    let model = LibraryItemDetailModel(item: .diamond(initial), library: library)
    #expect(await model.load())
    try await library.store.ingest(
      .diamond(featureProject("project", title: "Changed", status: "progress")),
      scope: library.scope)
    #expect(await model.load())
    #expect(model.item.title == "Changed")
    #expect(model.item.status == "progress")
  }

  @Test func diamondNotesLoadFromDownloadedSnapshotInDateOrder() async throws {
    let library = try localFeatureLibrary()
    let snapshot = try JSONDecoder().decode(LocalFullSnapshot.self, from: Data(#"""
    {
      "version":1,
      "projects":[{"id":"project","title":"Moon Garden","user":"feature-user","status":"progress","kit_category":"full","created":"2026-09-01","updated":"2026-09-01"}],
      "coloringBooks":[],"coloringPages":[],"coloringPageProgressNotes":[],
      "progressNotes":[
        {"id":"older","project":"project","content":"First","date":"2026-09-02","created":"2026-09-02","updated":"2026-09-02"},
        {"id":"newer","project":"project","content":"Next","date":"2026-09-03","created":"2026-09-03","updated":"2026-09-03"}
      ]
    }
    """#.utf8))
    try await library.store.ingestSnapshot(snapshot, scope: library.scope)
    let model = LibraryItemDetailModel(
      item: .diamond(featureProject("project", title: "Moon Garden", status: "progress")),
      library: library)
    #expect(await model.load())
    #expect(model.progressNotes.map(\.id) == ["newer", "older"])
  }
}

private final class LostNoteURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var snapshotAvailable = false
  nonisolated(unsafe) static var createRequests = 0
  nonisolated(unsafe) static var createSucceeds = false

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    if Self.createSucceeds, request.httpMethod == "POST" {
      respond(#"{"id":"created-note","project":"project","content":"Half finished","date":"1970-01-01","created":"2026-09-01","updated":"2026-09-01"}"#)
      return
    }
    guard request.url?.path == "/api/mobile/sync/snapshot" else {
      Self.createRequests += 1
      client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
      return
    }
    guard Self.snapshotAvailable else {
      client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
      return
    }
    respond(#"{"version":1,"projects":[{"id":"project","user":"feature-user","title":"Moon Garden","status":"wishlist","kit_category":"full","created":"2026-09-01","updated":"2026-09-01"}],"coloringBooks":[],"coloringPages":[],"progressNotes":[{"id":"saved-note","project":"project","content":"Half finished","date":"2026-09-01","created":"2026-09-01","updated":"2026-09-01"}],"coloringPageProgressNotes":[]}"#)
  }

  private func respond(_ body: String) {
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
