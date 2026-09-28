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

  @Test func pageStatusQueuesPlainStatusPatch() async throws {
    let library = try localFeatureLibrary()
    let page = featurePage("page", book: "book", number: 3)
    try await library.store.ingest(.book(featureBook("book", title: "Quiet Pages")), scope: library.scope)
    try await library.store.ingest(.page(page), scope: library.scope)
    let model = LibraryItemDetailModel(item: .page(page), library: library)
    #expect(await model.setStatus("in_progress"))
    #expect(model.statusSaveRevision == 1)
    #expect(model.item.status == "in_progress")
    let patch = try #require(await library.store.pendingOperations(scope: library.scope).last?.patch)
    #expect(patch == ["status": .string("in_progress")])
    try await library.close(removingData: false)
  }

  @Test func inlineDateEditsQueueDateOnlyStringsAndClear() async throws {
    let library = try localFeatureLibrary()
    let project = featureProject(
      "project", title: "Moon Garden", status: "completed", dateCompleted: "2026-09-01")
    try await library.store.ingest(.diamond(project), scope: library.scope)
    let model = LibraryItemDetailModel(item: .diamond(project), library: library)
    let day = try #require(DetailDateOnly.date("2026-09-17"))

    #expect(await model.setDate("date_completed", to: day))
    guard case .diamond(let saved) = model.item else { Issue.record("Expected project"); return }
    #expect(saved.dateCompleted?.hasPrefix("2026-09-17") == true)
    var patch = try #require(await library.store.pendingOperations(scope: library.scope).last?.patch)
    #expect(patch["date_completed"] == .string("2026-09-17"))
    #expect(patch["status"] == nil)

    #expect(await model.setDate("date_completed", to: nil))
    guard case .diamond(let cleared) = model.item else { Issue.record("Expected project"); return }
    #expect(cleared.dateCompleted?.nonEmpty == nil)
    let first = try #require(await library.store.pendingOperations(scope: library.scope).first)
    _ = try await library.store.acknowledge(
      scope: library.scope, operationID: first.id,
      record: .diamond(featureProject(
        "project", title: "Moon Garden", status: "completed", dateCompleted: "2026-09-17")))
    patch = try #require(await library.store.pendingOperations(scope: library.scope).first?.patch)
    #expect(patch["date_completed"] == .string(""))
    try await library.close(removingData: false)
  }

  @Test func inlineRenameAndSpecEditsSaveLocally() async throws {
    let library = try localFeatureLibrary()
    let project = featureProject("project", title: "Moon Garden")
    try await library.store.ingest(.diamond(project), scope: library.scope)
    let model = LibraryItemDetailModel(item: .diamond(project), library: library)
    #expect(await model.updateFields(["title": "Sun Garden", "kit_category": "mini"]))
    guard case .diamond(let saved) = model.item else { Issue.record("Expected project"); return }
    #expect(saved.title == "Sun Garden")
    #expect(saved.kitCategory == "mini")
    #expect(!(await model.updateFields([:])))
    try await library.close(removingData: false)
  }

  @Test func rejectedInlineEditKeepsSavedValueAndShowsError() async throws {
    let library = try localFeatureLibrary()
    let project = featureProject("project", title: "Moon Garden")
    try await library.store.ingest(.diamond(project), scope: library.scope)
    let model = LibraryItemDetailModel(item: .diamond(project), library: library)
    #expect(!(await model.updateFields(["total_pages": "100"])))
    #expect(model.item.title == "Moon Garden")
    #expect(model.editErrorMessage != nil)
    #expect(model.statusSaveRevision == 0)
    try await library.close(removingData: false)
  }

  @Test func dateOnlyStringUsesTheGivenTimeZone() throws {
    let instant = try #require(ISO8601DateFormatter().date(from: "2026-09-18T02:30:00Z"))
    #expect(DetailDateOnly.string(from: instant, timeZone: .gmt) == "2026-09-18")
    let pacific = try #require(TimeZone(identifier: "America/Los_Angeles"))
    #expect(DetailDateOnly.string(from: instant, timeZone: pacific) == "2026-09-17")
    let day = try #require(DetailDateOnly.date("2026-03-08", timeZone: pacific))
    #expect(DetailDateOnly.string(from: day, timeZone: pacific) == "2026-03-08")
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

    let saved = await model.addProgressNote(
      content: "Half finished", date: Date(timeIntervalSince1970: 0), photo: nil)
    #expect(!saved)
    #expect(model.unresolvedWriteState == .needsRefresh)
    #expect(model.mutationErrorMessage?.contains("Adding a progress note needs a connection") == true)
    #expect(model.mutationErrorMessage?.contains("refresh status before adding another note") == true)
    #expect(model.progressNotes.isEmpty)
    #expect(LostNoteURLProtocol.createRequests == 1)
    let duplicate = await model.addProgressNote(
      content: "Half finished", date: Date(timeIntervalSince1970: 0), photo: nil)
    #expect(!duplicate)
    #expect(LostNoteURLProtocol.createRequests == 1)

    LostNoteURLProtocol.snapshotAvailable = true
    #expect(await model.refreshUnresolvedWriteStatus())
    #expect(model.unresolvedWriteState == .refreshed)
    #expect(model.progressNotes.map(\.recordID) == ["saved-note"])
    #expect(model.lastAddedProgressNoteID == nil)
  }

  @Test(arguments: [false, true])
  func disconnectedPageWritesRequireRefreshBeforeRetry(isNote: Bool) async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OfflinePagePhotoURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://offline-page-photo.example.test")!,
      sessionStore: KeychainSessionStore(service: "OfflinePagePhotoTests.\(UUID().uuidString)"),
      urlSession: URLSession(configuration: configuration))
    await client.prepareOfflineSession(StoredSession(token: "example-token", userID: "feature-user"))
    let library = LibrarySession(
      client: client, userID: "feature-user", store: try LocalLibraryStore.inMemory())
    let page = featurePage("page", book: "book", number: 1)
    try await library.store.ingest(.book(featureBook("book", title: "Quiet Pages")), scope: library.scope)
    try await library.store.ingest(.page(page), scope: library.scope)
    let model = LibraryItemDetailModel(item: .page(page), library: library)
    #expect(await model.load())

    let photo = ProcessedDetailPhoto(
      data: Data([1, 2, 3]), fileName: "example.jpg", contentType: "image/jpeg")
    if isNote {
      #expect(!(await model.addProgressNote(content: "Half finished", date: .now, photo: nil)))
      #expect(model.mutationErrorMessage?.contains("Adding a progress note needs a connection") == true)
      #expect(model.mutationErrorMessage?.contains("refresh status before adding another note") == true)
      #expect(!(await model.addProgressNote(content: "Half finished", date: .now, photo: nil)))
    } else {
      #expect(!(await model.appendPagePhoto(photo)))
      #expect(model.mutationErrorMessage?.contains("Adding a photo needs a connection") == true)
      #expect(model.mutationErrorMessage?.contains("refresh status before starting another upload") == true)
      #expect(!(await model.appendPagePhoto(photo)))
    }
    #expect(model.unresolvedWriteState == .needsRefresh)
  }

  @Test func unsupportedBookNoteDoesNotChangeFollowingWriteRecovery() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OfflinePagePhotoURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://unsupported-book-note.example.test")!,
      sessionStore: KeychainSessionStore(service: "UnsupportedBookNoteTests.\(UUID().uuidString)"),
      urlSession: URLSession(configuration: configuration))
    await client.prepareOfflineSession(StoredSession(token: "example-token", userID: "feature-user"))
    let library = LibrarySession(
      client: client, userID: "feature-user", store: try LocalLibraryStore.inMemory())
    let book = featureBook("book", title: "Quiet Pages")
    let page = featurePage("page", book: book.id, number: 1)
    try await library.store.ingest(.book(book), scope: library.scope)
    try await library.store.ingest(.page(page), scope: library.scope)
    let model = LibraryItemDetailModel(item: .book(book), library: library)
    #expect(await model.load())

    #expect(!(await model.addProgressNote(content: "Progress", date: .now, photo: nil)))
    #expect(!model.isMutating)
    #expect(model.unresolvedWriteState == nil)
    #expect(model.mutationErrorMessage == nil)
    #expect(model.editErrorMessage == nil)

    await model.acceptSaved(.page(page))
    let photo = ProcessedDetailPhoto(
      data: Data([1, 2, 3]), fileName: "example.jpg", contentType: "image/jpeg")
    #expect(!(await model.appendPagePhoto(photo)))
    #expect(model.mutationErrorMessage?.contains("Adding a photo needs a connection") == true)
    #expect(model.mutationErrorMessage?.contains("Adding a progress note") == false)
  }

  @Test func confirmedNoteRevealClearsOnlyWhenThatNoteIsDeleted() async throws {
    LostNoteURLProtocol.snapshotAvailable = false
    LostNoteURLProtocol.createSucceeds = true
    LostNoteURLProtocol.deleteSucceeds = true
    defer {
      LostNoteURLProtocol.createSucceeds = false
      LostNoteURLProtocol.deleteSucceeds = false
    }
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
    try await library.store.ingestNote(
      DiamondProgressNoteRecord(
        id: "older-note", project: project.id, content: "Earlier work",
        date: "1969-12-31", image: nil, created: "1969-12-31",
        updated: "1969-12-31", expand: nil),
      scope: library.scope)
    let model = LibraryItemDetailModel(item: .diamond(project), library: library)
    #expect(await model.load())
    #expect(model.lastAddedProgressNoteID == nil)

    #expect(
      await model.addProgressNote(
        content: "Half finished", date: Date(timeIntervalSince1970: 0), photo: nil))
    #expect(model.lastAddedProgressNoteID == "created-note")
    #expect(model.progressNotes.map(\.recordID) == ["created-note", "older-note"])

    let older = try #require(model.progressNotes.first { $0.recordID == "older-note" })
    #expect(await model.deleteProgressNote(older) == nil)
    #expect(model.lastAddedProgressNoteID == "created-note")
    #expect(model.progressNotes.map(\.recordID) == ["created-note"])

    let created = try #require(model.progressNotes.first { $0.recordID == "created-note" })
    #expect(await model.deleteProgressNote(created) == nil)
    #expect(model.lastAddedProgressNoteID == nil)
    #expect(model.progressNotes.isEmpty)
  }

  @Test func pageNoteCreationDecodesColoringRecord() async throws {
    LostNoteURLProtocol.createPageSucceeds = true
    defer { LostNoteURLProtocol.createPageSucceeds = false }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LostNoteURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://saved-page-note.example.test")!,
      sessionStore: KeychainSessionStore(service: "SavedPageNoteTests.\(UUID().uuidString)"),
      urlSession: URLSession(configuration: configuration))
    await client.prepareOfflineSession(StoredSession(token: "example-token", userID: "feature-user"))
    let library = LibrarySession(
      client: client, userID: "feature-user", store: try LocalLibraryStore.inMemory())
    let book = featureBook("book", title: "Quiet Pages")
    let page = featurePage("page", book: book.id, number: 1)
    try await library.store.ingest(.book(book), scope: library.scope)
    try await library.store.ingest(.page(page), scope: library.scope)
    let model = LibraryItemDetailModel(item: .page(page), library: library)
    #expect(await model.load())

    #expect(
      await model.addProgressNote(
        content: "First colors", date: Date(timeIntervalSince1970: 0), photo: nil))
    #expect(model.lastAddedProgressNoteID == "created-coloring-note")
    #expect(model.progressNotes.count == 1)
    #expect(model.progressNotes.first?.collection == "coloring_page_progress_notes")
    #expect(model.progressNotes.first?.recordID == "created-coloring-note")
  }

  @Test func progressNotesKeepLoadedPagesAfterReloadsAndSaves() async throws {
    let library = try localFeatureLibrary()
    let project = featureProject("project", title: "Moon Garden")
    try await library.store.ingest(.diamond(project), scope: library.scope)
    for index in 0..<45 {
      let note = DiamondProgressNoteRecord(
        id: "note-\(index)", project: project.id, content: "Progress",
        date: "2026-09-01", image: nil, created: "2026-09-01",
        updated: "2026-09-01", expand: nil)
      try await library.store.ingestNote(note, scope: library.scope)
    }
    let model = LibraryItemDetailModel(item: .diamond(project), library: library)
    #expect(await model.load())
    #expect(model.progressNotes.count == 20)
    await model.loadMoreProgressNotes()
    let loadedIDs = model.progressNotes.map(\.recordID)
    #expect(loadedIDs.count == 40)
    #expect(await model.load())
    #expect(model.progressNotes.map(\.recordID) == loadedIDs)
    #expect(await model.setStatus("progress"))
    #expect(model.progressNotes.map(\.recordID) == loadedIDs)
    let edited: DiamondProjectRecord = try await library.update(
      collection: "projects", id: project.id, body: ["title": "Moon Garden updated"])
    await model.acceptSaved(.diamond(edited))
    #expect(model.progressNotes.map(\.recordID) == loadedIDs)
    #expect(model.canLoadMoreProgressNotes)
    await model.loadMoreProgressNotes()
    #expect(model.progressNotes.count == 45)
    #expect(!model.canLoadMoreProgressNotes)
    #expect(await model.load())
    #expect(model.progressNotes.count == 45)
    try await library.close(removingData: false)
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
    #expect(model.progressNotes.map(\.recordID) == ["newer", "older"])
  }

  @Test func pageNotesShareNewestFirstTimelineAndDeleteLocally() async throws {
    let library = try localFeatureLibrary()
    let book = featureBook("book", title: "Quiet Pages")
    let page = featurePage("page", book: book.id, number: 3)
    try await library.store.ingest(.book(book), scope: library.scope)
    try await library.store.ingest(.page(page), scope: library.scope)
    for (id, date) in [("older", "2026-09-02"), ("newer", "2026-09-03")] {
      try await library.store.ingestNote(
        ColoringProgressNoteRecord(
          id: id, user: library.userID, page: page.id, content: "**Progress**",
          date: date, image: nil, created: date, updated: date, expand: nil),
        scope: library.scope)
    }
    let model = LibraryItemDetailModel(item: .page(page), library: library)
    #expect(await model.load())
    #expect(model.progressNotes.map(\.recordID) == ["newer", "older"])
    #expect(model.progressNotes.allSatisfy { $0.collection == "coloring_page_progress_notes" })

    try await library.store.removeNote(
      kind: .coloring, id: "newer", scope: library.scope)
    #expect(await model.load())
    #expect(model.progressNotes.map(\.recordID) == ["older"])
  }
}

private final class LostNoteURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var snapshotAvailable = false
  nonisolated(unsafe) static var createRequests = 0
  nonisolated(unsafe) static var createSucceeds = false
  nonisolated(unsafe) static var createPageSucceeds = false
  nonisolated(unsafe) static var deleteSucceeds = false

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    if Self.createPageSucceeds, request.httpMethod == "POST",
      request.url?.path == "/api/collections/coloring_page_progress_notes/records"
    {
      respond(#"{"id":"created-coloring-note","user":"feature-user","page":"page","content":"First colors","date":"1970-01-01","created":"2026-09-01","updated":"2026-09-01"}"#)
      return
    }
    if Self.createSucceeds, request.httpMethod == "POST" {
      respond(#"{"id":"created-note","project":"project","content":"Half finished","date":"1970-01-01","created":"2026-09-01","updated":"2026-09-01"}"#)
      return
    }
    if Self.deleteSucceeds, request.httpMethod == "DELETE" {
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: nil)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocolDidFinishLoading(self)
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

private final class OfflinePagePhotoURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
  }
  override func stopLoading() {}
}
