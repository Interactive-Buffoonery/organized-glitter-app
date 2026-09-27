import Foundation
import Testing

@testable import OrganizedGlitter

struct LocalLibraryStoreTests {
  private let backendURL = URL(string: "https://data.example.test")!

  @Test
  func pendingEditAndSnapshotSurviveDiskRestart() async throws {
    let scope = LocalAccountScope(backendURL: backendURL, userID: "user-1")
    let database = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString)
      .appending(path: "library.store")
    let original = try project(id: "project-1", user: "user-1", title: "First")
    let operationID: UUID

    do {
      let store = try LocalLibraryStore(databaseURL: database)
      try await store.ingestSnapshot(snapshot(projects: [original]), scope: scope)
      _ = try await store.queueEdit(
        scope: scope, key: original.localRecordKey,
        patch: ["title": .string("Changed offline")])
      operationID = try #require(await store.pendingOperations(scope: scope).first?.id)
    }

    let reopened = try LocalLibraryStore(databaseURL: database)
    #expect(try await reopened.hasSnapshot(scope: scope))
    let entry = try #require(await reopened.entry(scope: scope, key: original.localRecordKey))
    #expect(entry.item.title == "Changed offline")
    #expect(entry.pending)
    #expect(try await reopened.pendingOperations(scope: scope).first?.id == operationID)
  }

  @Test
  func removalMarkerSurvivesRestartAndBlocksNewWrites() async throws {
    let scope = LocalAccountScope(backendURL: backendURL, userID: "user-1")
    let database = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString)
      .appending(path: "library.store")
    let item = try project(id: "project-1", user: "user-1", title: "Private")
    do {
      let store = try LocalLibraryStore(databaseURL: database)
      try await store.ingestSnapshot(snapshot(projects: [item]), scope: scope)
      try await store.beginRemoval(scope: scope)
      try await store.removeScope(scope)
    }

    let reopened = try LocalLibraryStore(databaseURL: database)
    #expect(try await reopened.pendingRemovals() == [scope])
    #expect(try await reopened.entries(scope: scope).isEmpty)
    do {
      try await reopened.saveUser(
        UserRecord(
          id: scope.userID, email: nil, verified: true, username: nil, name: nil,
          avatar: nil, timezone: nil, themePreference: nil, created: nil, updated: nil),
        scope: scope)
      Issue.record("Expected removal marker to reject a stale account save")
    } catch LocalLibraryError.storageUnavailable {}
    do {
      _ = try await reopened.queueEdit(
        scope: scope, key: item.localRecordKey, patch: ["title": .string("Stale")])
      Issue.record("Expected removal marker to reject a stale edit")
    } catch LocalLibraryError.storageUnavailable {}
    try await reopened.finishRemoval(scope: scope)
    #expect(try await reopened.pendingRemovals().isEmpty)
  }

  @Test
  func projectionIncludesSavedValuesAndPendingCount() async throws {
    let scope = LocalAccountScope(backendURL: backendURL, userID: "user-1")
    let store = try LocalLibraryStore.inMemory()
    let first = try project(id: "project-1", user: "user-1", title: "First")
    let second = try project(id: "project-2", user: "user-1", title: "Second")
    try await store.ingestSnapshot(snapshot(projects: [first, second]), scope: scope)
    _ = try await store.queueEdit(
      scope: scope, key: second.localRecordKey, patch: ["title": .string("Offline")])

    let projection = try await store.projection(scope: scope)
    #expect(projection.hasSnapshot)
    #expect(projection.pendingCount == 1)
    #expect(projection.entries.count == 2)
    #expect(projection.entries.first(where: { $0.item.recordID == second.recordID })?.item.title == "Offline")
    #expect(projection.progressNotes.isEmpty)
    #expect(projection.coloringPageProgressNotes.isEmpty)
  }

  @Test
  func nextPendingOperationUsesStableRecordOrder() async throws {
    let scope = LocalAccountScope(backendURL: backendURL, userID: "user-1")
    let store = try LocalLibraryStore.inMemory()
    let first = try project(id: "project-a", user: "user-1", title: "First")
    let second = try project(id: "project-z", user: "user-1", title: "Second")
    try await store.ingestSnapshot(snapshot(projects: [second, first]), scope: scope)
    _ = try await store.queueEdit(
      scope: scope, key: second.localRecordKey, patch: ["title": .string("Z")])
    _ = try await store.queueEdit(
      scope: scope, key: first.localRecordKey, patch: ["title": .string("A")])

    let next = try #require(await store.nextPendingOperation(scope: scope))
    #expect(next.key == first.localRecordKey)
    _ = try await store.acknowledge(
      scope: scope, operationID: next.id,
      record: try project(id: "project-a", user: "user-1", title: "A"))
    #expect(try await store.nextPendingOperation(scope: scope)?.key == second.localRecordKey)
  }

  @Test
  func responseForFirstEditKeepsLaterEdit() async throws {
    let scope = LocalAccountScope(backendURL: backendURL, userID: "user-1")
    let store = try LocalLibraryStore.inMemory()
    let original = try project(id: "project-1", user: "user-1", title: "First")
    try await store.ingestSnapshot(snapshot(projects: [original]), scope: scope)
    _ = try await store.queueEdit(
      scope: scope, key: original.localRecordKey,
      patch: ["title": .string("First edit")])
    let first = try #require(await store.pendingOperations(scope: scope).first)
    _ = try await store.queueEdit(
      scope: scope, key: original.localRecordKey,
      patch: ["title": .string("Second edit")])

    let server = try project(id: "project-1", user: "user-1", title: "First edit")
    _ = try await store.acknowledge(scope: scope, operationID: first.id, record: server)
    let entry = try #require(await store.entry(scope: scope, key: original.localRecordKey))
    #expect(entry.item.title == "Second edit")
    #expect(entry.pending)
    let next = try #require(await store.pendingOperations(scope: scope).first)
    #expect(next.id != first.id)
    #expect(next.base["title"] == .string("First edit"))
    #expect(next.patch["title"] == .string("Second edit"))
  }

  @Test
  func replayWithNewerServerEditDoesNotRebaseLaterLocalEdit() async throws {
    let scope = LocalAccountScope(backendURL: backendURL, userID: "user-1")
    let store = try LocalLibraryStore.inMemory()
    let original = try project(id: "project-1", user: "user-1", title: "A")
    try await store.ingestSnapshot(snapshot(projects: [original]), scope: scope)
    _ = try await store.queueEdit(
      scope: scope, key: original.localRecordKey, patch: ["title": .string("B")])
    let first = try #require(await store.pendingOperations(scope: scope).first)
    _ = try await store.queueEdit(
      scope: scope, key: original.localRecordKey, patch: ["title": .string("C")])

    // A replay can return D: the server accepted B, its response was lost,
    // then another client changed the title before this client retried.
    let replayed = try project(id: "project-1", user: "user-1", title: "D")
    _ = try await store.acknowledge(
      scope: scope, operationID: first.id, record: replayed)

    let entry = try #require(await store.entry(scope: scope, key: original.localRecordKey))
    #expect(entry.item.title == "C")
    #expect(entry.conflict == .changedOnServer)
    #expect(try await store.pendingOperations(scope: scope).isEmpty)
    let changes = try await store.conflictChanges(scope: scope, key: original.localRecordKey)
    #expect(changes.first?.local == .string("C"))
    #expect(changes.first?.server == .string("D"))
  }

  @Test
  func conflictShowsBothValuesAndCanRetainLocalEdit() async throws {
    let scope = LocalAccountScope(backendURL: backendURL, userID: "user-1")
    let store = try LocalLibraryStore.inMemory()
    let original = try project(id: "project-1", user: "user-1", title: "First")
    try await store.ingestSnapshot(snapshot(projects: [original]), scope: scope)
    _ = try await store.queueEdit(
      scope: scope, key: original.localRecordKey,
      patch: ["title": .string("My title")])
    let pending = try #require(await store.pendingOperations(scope: scope).first)
    let server = try project(id: "project-1", user: "user-1", title: "Other title")
    _ = try await store.recordConflict(
      scope: scope, operationID: pending.id, server: server)

    let entry = try #require(await store.entry(scope: scope, key: original.localRecordKey))
    #expect(entry.item.title == "My title")
    #expect(entry.conflict == .changedOnServer)
    let changes = try await store.conflictChanges(scope: scope, key: original.localRecordKey)
    #expect(changes.count == 1)
    #expect(changes.first?.local == .string("My title"))
    #expect(changes.first?.server == .string("Other title"))
    _ = try await store.resolveConflict(
      scope: scope, key: original.localRecordKey, retainLocal: true)
    let retried = try #require(await store.pendingOperations(scope: scope).first)
    #expect(retried.id != pending.id)
    #expect(retried.base["title"] == .string("Other title"))
    #expect(retried.patch["title"] == .string("My title"))
  }

  @Test
  func lifecycleConflictShowsComparedFieldsAlongsideEditedFields() async throws {
    let scope = LocalAccountScope(backendURL: backendURL, userID: "user-1")
    let store = try LocalLibraryStore.inMemory()
    let original = try project(id: "project-1", user: "user-1", title: "First")
    try await store.ingestSnapshot(snapshot(projects: [original]), scope: scope)
    _ = try await store.queueEdit(
      scope: scope, key: original.localRecordKey,
      patch: ["status": .string("progress")])
    let operation = try #require(await store.nextPendingOperation(scope: scope))
    let server = try project(
      id: "project-1", user: "user-1", title: "First",
      dateStarted: "2026-09-01 00:00:00.000Z")
    _ = try await store.recordConflict(
      scope: scope, operationID: operation.id, server: server)

    let changes = try await store.conflictChanges(scope: scope, key: original.localRecordKey)
    let date = try #require(changes.first(where: { $0.field == "date_started" }))
    #expect(date.local == .null)
    #expect(date.server == .string("2026-09-01 00:00:00.000Z"))
    #expect(date.isComparisonOnly)
    let status = try #require(changes.first(where: { $0.field == "status" }))
    #expect(status.local == .string("progress"))
    #expect(!status.isComparisonOnly)
  }

  @Test
  func scopesKeepAccountsAndBackendsSeparate() async throws {
    let store = try LocalLibraryStore.inMemory()
    let first = LocalAccountScope(backendURL: backendURL, userID: "user-1")
    let otherUser = LocalAccountScope(backendURL: backendURL, userID: "user-2")
    let otherBackend = LocalAccountScope(
      backendURL: URL(string: "https://another.example.test")!, userID: "user-1")
    let item = try project(id: "project-1", user: "user-1", title: "Private")
    try await store.ingestSnapshot(snapshot(projects: [item]), scope: first)

    #expect(try await store.entries(scope: first).count == 1)
    #expect(try await store.entries(scope: otherUser).isEmpty)
    #expect(try await store.entries(scope: otherBackend).isEmpty)
    #expect(!(try await store.hasSnapshot(scope: otherUser)))
    #expect(!(try await store.hasSnapshot(scope: otherBackend)))
  }

  @Test
  func invalidSnapshotCannotReplaceExistingData() async throws {
    let scope = LocalAccountScope(backendURL: backendURL, userID: "user-1")
    let store = try LocalLibraryStore.inMemory()
    let original = try project(id: "project-1", user: "user-1", title: "Private")
    let another = try project(id: "project-2", user: "user-2", title: "Wrong owner")
    try await store.ingestSnapshot(snapshot(projects: [original]), scope: scope)
    do {
      try await store.ingestSnapshot(snapshot(projects: [another]), scope: scope)
      Issue.record("Expected account-scope validation to fail")
    } catch LocalLibraryError.wrongAccount {}
    #expect(try await store.entries(scope: scope).map(\.item.title) == ["Private"])
  }

  @Test
  func confirmedRemovalDeletesOnlyRelatedRecordsAndNotes() async throws {
    let scope = LocalAccountScope(backendURL: backendURL, userID: "user-1")
    let store = try LocalLibraryStore.inMemory()
    let firstProject = try project(id: "project-1", user: "user-1", title: "First")
    let secondProject = try project(id: "project-2", user: "user-1", title: "Second")
    let books = try ["book-1", "book-2"].map { id in
      try decode(ColoringBookRecord.self, [
        "id": id, "user": "user-1", "title": id, "status": "wishlist",
        "total_pages": 1, "created": "2026-01-01", "updated": "2026-01-01",
      ])
    }
    let pages = try [("page-1", "book-1"), ("page-2", "book-2")].map { id, book in
      try decode(ColoringPageRecord.self, [
        "id": id, "book": book, "page_number": 1, "status": "wishlist",
        "photos": [], "created": "2026-01-01", "updated": "2026-01-01",
      ])
    }
    let diamondNotes = try ["project-1", "project-2"].map { project in
      try decode(DiamondProgressNoteRecord.self, [
        "id": "note-\(project)", "project": project, "content": "Note", "date": "2026-01-01",
        "created": "2026-01-01", "updated": "2026-01-01",
      ])
    }
    let coloringNotes = try ["page-1", "page-2"].map { page in
      try decode(ColoringProgressNoteRecord.self, [
        "id": "note-\(page)", "user": "user-1", "page": page, "content": "Note",
        "date": "2026-01-01", "created": "2026-01-01", "updated": "2026-01-01",
      ])
    }
    try await store.ingestSnapshot(LocalFullSnapshot(
      version: 1, projects: [firstProject, secondProject].compactMap {
        if case .diamond(let record) = $0 { return record }
        return nil
      }, coloringBooks: books, coloringPages: pages,
      progressNotes: diamondNotes, coloringPageProgressNotes: coloringNotes), scope: scope)
    let projection = try await store.projection(scope: scope)
    #expect(Set(projection.progressNotes.map(\.project)) == ["project-1", "project-2"])
    #expect(Set(projection.coloringPageProgressNotes.map(\.page)) == ["page-1", "page-2"])

    try await store.removeConfirmed(
      scope: scope, key: LocalRecordKey(kind: .project, id: "project-1"))
    try await store.removeConfirmed(
      scope: scope, key: LocalRecordKey(kind: .book, id: "book-1"))

    let records = try await store.entries(scope: scope)
    #expect(Set(records.map(\.item.recordID)) == ["project-2", "book-2", "page-2"])
    let remainingNotes = try await store.notes(scope: scope)
    #expect(remainingNotes.diamonds.map(\.project) == ["project-2"])
    #expect(remainingNotes.coloring.map(\.page) == ["page-2"])
  }

  @Test
  func pageDecodesWhenExpandedBookOmitsUser() throws {
    let page = try decode(ColoringPageRecord.self, [
      "id": "page-1", "book": "book-1", "page_number": 1, "status": "wishlist",
      "photos": [], "created": "2026-01-01", "updated": "2026-01-01",
      "expand": ["book": ["id": "book-1", "title": "Book"]],
    ])
    #expect(page.expand?.book?.title == "Book")
    #expect(page.expand?.book?.user == nil)
  }

  @Test
  func databaseOpenFailureIsReported() throws {
    let regularFile = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString)
    try Data().write(to: regularFile)
    do {
      _ = try LocalLibraryStore(databaseURL: regularFile.appending(path: "library.store"))
      Issue.record("Expected storage opening to fail")
    } catch {}
  }

  private func snapshot(projects: [LibraryItem]) -> LocalFullSnapshot {
    LocalFullSnapshot(
      version: 1,
      projects: projects.compactMap {
        if case .diamond(let record) = $0 { return record }
        return nil
      },
      coloringBooks: [], coloringPages: [], progressNotes: [],
      coloringPageProgressNotes: [])
  }

  private func project(
    id: String, user: String, title: String, dateStarted: String? = nil
  ) throws -> LibraryItem {
    var object: [String: Any] = [
      "id": id, "user": user, "title": title, "status": "wishlist",
      "kit_category": "full", "created": "2026-01-01 00:00:00.000Z",
      "updated": "2026-01-01 00:00:00.000Z",
    ]
    if let dateStarted { object["date_started"] = dateStarted }
    let data = try JSONSerialization.data(withJSONObject: object)
    return .diamond(try JSONDecoder().decode(DiamondProjectRecord.self, from: data))
  }

  private func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
    try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
  }
}
