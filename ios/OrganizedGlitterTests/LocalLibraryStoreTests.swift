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

  private func project(id: String, user: String, title: String) throws -> LibraryItem {
    let object: [String: Any] = [
      "id": id, "user": user, "title": title, "status": "wishlist",
      "kit_category": "full", "created": "2026-01-01 00:00:00.000Z",
      "updated": "2026-01-01 00:00:00.000Z",
    ]
    let data = try JSONSerialization.data(withJSONObject: object)
    return .diamond(try JSONDecoder().decode(DiamondProjectRecord.self, from: data))
  }
}
