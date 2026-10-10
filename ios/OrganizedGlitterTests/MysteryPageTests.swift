import Foundation
import Testing

@testable import OrganizedGlitter

struct MysteryPageTests {
  @Test
  func revealTrimsAnswerAndUsesCapturedDay() throws {
    #expect(try MysteryRevealWrite.reveal(subject: "  Garden\n", day: "2026-10-10", today: "2026-10-10")
      == ["revealed_subject": "Garden", "revealed_at": "2026-10-10"])
    #expect(throws: MysteryRevealError.emptySubject) {
      try MysteryRevealWrite.reveal(subject: " \n", day: "2026-10-10", today: "2026-10-10")
    }
    #expect(throws: MysteryRevealError.invalidDate) {
      try MysteryRevealWrite.reveal(subject: "Garden", day: "2026-02-30", today: "2026-10-10")
    }
    #expect(throws: MysteryRevealError.futureDate) {
      try MysteryRevealWrite.reveal(subject: "Garden", day: "2026-10-11", today: "2026-10-10")
    }
    #expect(throws: MysteryRevealError.invalidDate) {
      try MysteryRevealWrite.reveal(subject: "Garden", day: "2026-10-10 00:00:00", today: "2026-10-10")
    }
  }

  @Test
  func answerAndHideNeverChangeCompletion() throws {
    #expect(try MysteryRevealWrite.editAnswer("  Flowers  ") == ["revealed_subject": "Flowers"])
    #expect(MysteryRevealWrite.hide == ["revealed_subject": "", "revealed_at": ""])
    #expect(throws: MysteryRevealError.emptySubject) { try MysteryRevealWrite.editAnswer(" ") }
  }

  @Test
  func spoilerProjectionUsesParentMysteryFlagAndLegacyAnswer() {
    let unrevealed = page(subject: " \n")
    #expect(MysteryPagePresentation(page: unrevealed, isMystery: true).hidesThumbnail)
    #expect(MysteryPagePresentation(page: unrevealed, isMystery: true).title == "Page 12")
    #expect(!MysteryPagePresentation(page: unrevealed, isMystery: false).hidesThumbnail)
    let legacy = page(subject: "  Garden  ")
    let revealed = MysteryPagePresentation(page: legacy, isMystery: true)
    #expect(revealed.isRevealed)
    #expect(!revealed.hidesThumbnail)
    #expect(revealed.title == "Garden")
  }

  @Test
  func dateOnlyParsingAndExpansionPreserveRevealDay() {
    let original = page(subject: "Garden", day: "2026-10-09 00:00:00.000Z")
    #expect(original.withExpand(nil).revealedAt == original.revealedAt)
    #expect(DetailDateOnly.date(original.revealedAt!, timeZone: .gmt)
      == DetailDateOnly.date("2026-10-09", timeZone: .gmt))
    #expect(DetailDateOnly.date("2026-02-30", timeZone: .gmt) == nil)
  }

  @Test
  func revealQueueSurvivesRestartAndHidePreservesLifecycle() async throws {
    let scope = LocalAccountScope(backendURL: URL(string: "https://mystery.example.test")!, userID: "feature-user")
    let database = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "library.store")
    let original = page(subject: nil)
    let operationID: UUID
    do {
      let store = try LocalLibraryStore(databaseURL: database)
      try await store.ingestSnapshot(snapshot(original), scope: scope)
      _ = try await store.queueEdit(scope: scope, key: LibraryItem.page(original).localRecordKey,
        patch: ["revealed_subject": .string("Garden"), "revealed_at": .string("2026-10-10")])
      let pending = try #require(await store.pendingOperations(scope: scope).first)
      operationID = pending.id
      #expect(Set(pending.base.keys) == ["status", "started_at", "completed_at", "revealed_subject", "revealed_at"])
      #expect(pending.base["status"] == .string("completed"))
    }
    let store = try LocalLibraryStore(databaseURL: database)
    #expect(try await store.pendingOperations(scope: scope).first?.id == operationID)
    let other = LocalAccountScope(backendURL: scope.backendURL, userID: "other-user")
    #expect(try await store.pendingOperations(scope: other).isEmpty)
    _ = try await store.queueEdit(scope: scope, key: LibraryItem.page(original).localRecordKey,
      patch: MysteryRevealWrite.hide.mapValues(LocalJSONValue.string))
    let entry = try #require(await store.entry(scope: scope, key: LibraryItem.page(original).localRecordKey))
    guard case .page(let hidden) = entry.item else { Issue.record("Expected page"); return }
    #expect(hidden.revealedSubject == "")
    #expect(hidden.revealedAt == "")
    #expect(hidden.status == original.status)
    #expect(hidden.completedAt == original.completedAt)
    #expect(hidden.startedAt == original.startedAt)
  }

  @Test
  func editPreservesDateAndConflictRetainsAnswerAndLifecycleComparison() async throws {
    let scope = LocalAccountScope(backendURL: URL(string: "https://mystery.example.test")!, userID: "feature-user")
    let store = try LocalLibraryStore.inMemory()
    let original = page(subject: "Garden", day: "2026-10-09")
    let key = LibraryItem.page(original).localRecordKey
    try await store.ingestSnapshot(snapshot(original), scope: scope)
    _ = try await store.queueEdit(scope: scope, key: key,
      patch: try MysteryRevealWrite.editAnswer("My answer").mapValues(LocalJSONValue.string))
    let pending = try #require(await store.pendingOperations(scope: scope).first)
    #expect(pending.base["revealed_at"] == .string("2026-10-09"))
    #expect(pending.patch["revealed_at"] == nil)
    let entry = try #require(await store.entry(scope: scope, key: key))
    guard case .page(let edited) = entry.item else { Issue.record("Expected page"); return }
    #expect(edited.revealedAt == original.revealedAt)
    _ = try await store.recordConflict(scope: scope, operationID: pending.id,
      server: .page(page(subject: "Server answer", day: "2026-10-08", status: "in_progress")))
    let changes = try await store.conflictChanges(scope: scope, key: key)
    #expect(changes.contains { $0.field == "revealed_subject" && $0.local == .string("My answer") && !$0.isComparisonOnly })
    #expect(changes.contains { $0.field == "status" && $0.isComparisonOnly })
    #expect(changes.contains { $0.field == "revealed_at" && $0.isComparisonOnly })
    #expect(try await store.entry(scope: scope, key: key)?.conflict == .changedOnServer)
  }

  @MainActor
  @Test
  func mysteryLookupUsesOwnedCachedBookAndClearsWithScope() async throws {
    let library = try localFeatureLibrary()
    var book = featureBook("book", title: "Mystery")
    book.isMystery = true
    try await library.store.ingestSnapshot(LocalFullSnapshot(version: 1, projects: [], coloringBooks: [book],
      coloringPages: [], progressNotes: [], coloringPageProgressNotes: []), scope: library.scope)
    try await library.loadLocal()
    #expect(library.isMysteryBook("book"))
    #expect(!library.isMysteryBook("unknown"))
    _ = try await library.store.queueEdit(scope: library.scope,
      key: LibraryItem.book(book).localRecordKey, patch: ["is_mystery": .bool(false)])
    try await library.loadLocal()
    #expect(!library.isMysteryBook("book"))
    try await library.close(removingData: false)
    #expect(!library.isMysteryBook("book"))
  }

  @MainActor
  @Test
  func detailSavesRevealAndHideThroughLibrarySession() async throws {
    let library = try localFeatureLibrary()
    let original = page(subject: nil)
    try await library.store.ingestSnapshot(snapshot(original), scope: library.scope)
    try await library.loadLocal()
    let model = LibraryItemDetailModel(item: .page(original), library: library)
    #expect(await model.updateFields(try MysteryRevealWrite.reveal(subject: "Garden", day: "2026-10-10", today: "2026-10-10")))
    guard case .page(let revealed) = model.item else { Issue.record("Expected page"); return }
    #expect(revealed.revealedSubject == "Garden")
    #expect(revealed.revealedAt == "2026-10-10")
    #expect(await model.updateFields(MysteryRevealWrite.hide))
    guard case .page(let hidden) = model.item else { Issue.record("Expected page"); return }
    #expect(hidden.revealedSubject == "")
    #expect(hidden.revealedAt == "")
    #expect(hidden.status == original.status)
    #expect(hidden.completedAt == original.completedAt)
    try await library.close(removingData: false)
  }

  private func page(subject: String?, day: String? = nil, status: String = "completed") -> ColoringPageRecord {
    var result = ColoringPageRecord(id: "page", book: "book", pageNumber: 12, status: status,
      photos: ["private.png"], revealedSubject: subject, completedAt: "2026-10-01", startedAt: "2026-09-01",
      created: "2026-09-01", updated: "2026-10-01", expand: nil)
    result.revealedAt = day
    return result
  }

  private func snapshot(_ page: ColoringPageRecord) -> LocalFullSnapshot {
    LocalFullSnapshot(version: 1, projects: [], coloringBooks: [featureBook("book", title: "Mystery")],
      coloringPages: [page], progressNotes: [], coloringPageProgressNotes: [])
  }
}
