import Foundation
import Testing
@testable import OrganizedGlitter

@MainActor
struct LibraryRandomizerTests {
  private let verticals = VerticalPreferences(diamondPainting: true, coloringBooks: true)

  private func seed(_ items: [LibraryItem], library: LibrarySession) async throws {
    for item in items { try await library.store.ingest(item, scope: library.scope) }
    try await library.loadLocal()
  }

  @Test(arguments: RandomizerMode.allCases)
  func approvedCompletionCopyUsesNeutralItemTitle(mode: RandomizerMode) async throws {
    let library = try localFeatureLibrary()
    try await seed([.diamond(featureProject("project", title: "Project", status: "progress")),
      .book(featureBook("book", title: "Book", status: "in_progress")),
      .page(featurePage("page", book: "book", number: 1, status: "in_progress"))], library: library)
    let candidate = try #require(library.randomizerCandidates(mode: mode, verticals: verticals).first)
    #expect(RandomizerPageCopy.announcement(candidate) == "Spin complete! Selected: \(candidate.title)")
    #expect(RandomizerPageCopy.status("in_stash", mode: .book) == BookStatus.inStash.label)
  }

  @Test func defaultsUseRawStatusesForEachMode() async throws {
    let library = try localFeatureLibrary()
    try await seed([
      .diamond(featureProject("active", title: "Active", status: "progress")),
      .diamond(featureProject("label", title: "Label", status: "In progress")),
      .diamond(featureProject("stash", title: "Stash", status: "stash")),
      .diamond(featureProject("kitted", title: "Kitted", status: "kitted")),
      .book(featureBook("active", title: "Active", status: "in_progress")),
      .book(featureBook("stash", title: "Stash", status: "in_stash")),
      .page(featurePage("palette", book: "active", number: 1, status: "palette_chosen")),
      .page(featurePage("active", book: "active", number: 2, status: "in_progress")),
      .page(featurePage("waiting", book: "active", number: 3)),
    ], library: library)
    #expect(library.randomizerCandidates(mode: .diamond, verticals: verticals).map(\.item.recordID)
      == ["active"])
    #expect(library.randomizerCandidates(mode: .book, verticals: verticals).map(\.item.recordID)
      == ["active"])
    #expect(library.randomizerCandidates(mode: .page, verticals: verticals).map(\.item.recordID)
      == ["active", "palette"])
    #expect(library.randomizerCandidates(mode: .diamond, statuses: ["kitted"],
      verticals: verticals).map(\.item.recordID) == ["kitted"])
    #expect(library.randomizerCandidates(mode: .page, statuses: [], verticals: verticals).isEmpty)
  }

  @Test func ownershipRequiresCurrentParentAndExcludesDeletedTargets() throws {
    let foreignBook = ColoringBookRecord(
      id: "foreign", user: "another-account", title: "Foreign", series: nil,
      status: "in_progress", totalPages: 2, completedPages: nil, completionPercentage: nil,
      coverImage: nil, publisher: nil, illustrator: nil, created: "", updated: "", expand: nil)
    func entry(_ item: LibraryItem, _ conflict: LocalConflict? = nil) -> LocalLibraryEntry {
      LocalLibraryEntry(item: item, pending: conflict != nil, conflict: conflict)
    }
    let entries = [
      entry(.book(featureBook("owned", title: "Owned"))),
      entry(.book(foreignBook)),
      entry(.book(featureBook("deleted", title: "Deleted")), .deletedOnServer),
      entry(.page(featurePage("owned-page", book: "owned", number: 1)), .changedOnServer),
      entry(.page(featurePage("foreign-page", book: "foreign", number: 1))),
      entry(.page(featurePage("orphan", book: "missing", number: 1))),
      entry(.page(featurePage("deleted-parent", book: "deleted", number: 1))),
      entry(.page(featurePage("deleted-page", book: "owned", number: 2)), .deletedOnServer),
      entry(.diamond(featureProject("foreign", title: "Foreign", user: "another-account"))),
    ]
    let pages = RandomizerCandidate.owned(entries: entries, userID: "feature-user", mode: .page)
    #expect(pages.map(\.item.recordID) == ["owned-page"])
    #expect(pages.first?.bookTitle == "Owned")
    #expect(RandomizerCandidate.owned(entries: entries, userID: "feature-user", mode: .book)
      .map(\.item.recordID) == ["owned"])
    #expect(RandomizerCandidate.owned(entries: entries, userID: "feature-user", mode: .diamond)
      .isEmpty)
  }

  @Test func sharedProjectionPartitionsAndDeduplicatesOwnedRecords() {
    func entry(_ item: LibraryItem, _ conflict: LocalConflict? = nil) -> LocalLibraryEntry {
      LocalLibraryEntry(item: item, pending: conflict != nil, conflict: conflict)
    }
    let entries = [
      entry(.diamond(featureProject("shared", title: "First", updated: "2026-10-01"))),
      entry(.diamond(featureProject("shared", title: "Duplicate", updated: "2026-10-10"))),
      entry(.diamond(featureProject("recent", title: "Recent", updated: "2026-10-09"))),
      entry(.diamond(featureProject("foreign", title: "Foreign", user: "another-account"))),
      entry(.book(featureBook("shared", title: "First book"))),
      entry(.book(featureBook("shared", title: "Latest parent title"))),
      entry(.book(featureBook("deleted", title: "Deleted")), .deletedOnServer),
      entry(.page(featurePage("shared", book: "shared", number: 1))),
      entry(.page(featurePage("shared", book: "shared", number: 2))),
      entry(.page(featurePage("orphan", book: "deleted", number: 1))),
      entry(.page(featurePage("removed", book: "shared", number: 3)), .deletedOnServer),
    ]
    let projection = RandomizerCandidate.ownedByMode(entries: entries, userID: "feature-user")
    #expect(projection[.diamond]?.map(\.title) == ["Recent", "First"])
    #expect(projection[.book]?.map(\.title) == ["First book"])
    #expect(projection[.page]?.map(\.item.recordID) == ["shared"])
    #expect(projection[.page]?.first?.bookTitle == "Latest parent title")
    if case .page(let page) = projection[.page]?.first?.item {
      #expect(page.pageNumber == 1)
    } else {
      Issue.record("Expected the first owned page")
    }
  }

  @Test func selectionUsesIDsAndDisabledCraftsHaveNoCandidates() async throws {
    let library = try localFeatureLibrary()
    try await seed([
      .diamond(featureProject("one", title: "Same title", status: "progress")),
      .diamond(featureProject("two", title: "Same title", status: "progress")),
      .book(featureBook("one", title: "Same title", status: "in_progress")),
      .page(featurePage("page", book: "one", number: 1, status: "in_progress")),
    ], library: library)
    let key = LocalRecordKey(kind: .project, id: "two")
    #expect(library.randomizerCandidates(mode: .diamond, selectedIDs: [key],
      verticals: verticals).map(\.id) == [key])
    #expect(library.randomizerCandidates(mode: .diamond,
      selectedIDs: [LocalRecordKey(kind: .book, id: "one")], verticals: verticals).isEmpty)
    let disabled = VerticalPreferences(diamondPainting: false, coloringBooks: false)
    for mode in RandomizerMode.allCases {
      #expect(library.randomizerCandidates(mode: mode, verticals: disabled).isEmpty)
    }
  }

  @Test func selectionFreezesCandidatesAndWinnerAcrossLocalChanges() async throws {
    let library = try localFeatureLibrary()
    try await seed([
      .diamond(featureProject("first", title: "Original", status: "progress")),
      .diamond(featureProject("second", title: "Second", status: "progress")),
    ], library: library)
    let model = LibraryRandomizer(library: library)
    let spin = try #require(model.beginSelection(mode: .diamond, verticals: verticals))
    let frozen = try #require(model.selection)
    #expect(model.currentWinner(verticals: verticals) == nil)
    #expect(model.beginSelection(mode: .book, verticals: verticals) == nil)
    try await seed([.diamond(featureProject(frozen.winner.item.recordID,
      title: "Edited", status: "completed"))], library: library)
    #expect(model.selection == frozen)
    model.finishSelection(id: UUID())
    #expect(model.isSelecting)
    model.finishSelection(id: spin)
    #expect(!model.isSelecting)
    #expect(model.currentWinner(verticals: verticals)?.title == "Edited")
    #expect(model.selection == frozen)
    let landed = try #require(model.wheelSpin)
    #expect(frozen.candidates[try #require(RandomizerWheelGeometry.indexUnderPointer(
      rotation: landed.endRotation, count: landed.count))].id == frozen.winner.id)
    #expect(model.currentWinner(verticals:
      VerticalPreferences(diamondPainting: false, coloringBooks: true)) == nil)
    try await library.close(removingData: false)
    #expect(model.currentWinner(verticals: verticals) == nil)
    #expect(model.selection == frozen)
  }

  @Test func emptySingleAndResetSelectionsRejectStaleCompletions() async throws {
    let library = try localFeatureLibrary()
    let model = LibraryRandomizer(library: library)
    #expect(model.beginSelection(mode: .diamond, verticals: verticals) == nil)
    #expect(!model.isSelecting)
    try await seed([.diamond(featureProject("only", title: "Only", status: "progress"))],
      library: library)
    let old = try #require(model.beginSelection(mode: .diamond, verticals: verticals))
    #expect(model.selection?.winner.item.recordID == "only")
    model.reset()
    let current = try #require(model.beginSelection(mode: .diamond, verticals: verticals))
    model.finishSelection(id: old)
    #expect(model.isSelecting)
    model.finishSelection(id: current)
    #expect(model.currentWinner(verticals: verticals)?.recordID == "only")
    #expect(model.beginSelection(mode: .diamond, selectedIDs: [], verticals: verticals) == nil)
    #expect(model.selection == nil)
  }

  @Test func reopeningRejectsRemovedTargetAndRemovedBookParent() async throws {
    let library = try localFeatureLibrary()
    try await seed([
      .book(featureBook("book", title: "Book", status: "in_progress")),
      .page(featurePage("page", book: "book", number: 1, status: "in_progress")),
    ], library: library)
    let model = LibraryRandomizer(library: library)
    let spin = try #require(model.beginSelection(mode: .page, verticals: verticals))
    model.finishSelection(id: spin)
    #expect(model.currentWinner(verticals: verticals)?.recordID == "page")
    try await library.store.removeConfirmed(scope: library.scope,
      key: LocalRecordKey(kind: .book, id: "book"))
    try await library.loadLocal()
    #expect(model.currentWinner(verticals: verticals) == nil)
    try await library.store.removeConfirmed(scope: library.scope,
      key: LocalRecordKey(kind: .page, id: "page"))
    try await library.loadLocal()
    #expect(model.currentWinner(verticals: verticals) == nil)
  }

  @Test func candidatesReadPendingLocalEditsAndStayAccountScoped() async throws {
    let library = try localFeatureLibrary()
    try await seed([.diamond(featureProject("shared", title: "Original", status: "progress"))],
      library: library)
    _ = try await library.store.queueEdit(scope: library.scope,
      key: LocalRecordKey(kind: .project, id: "shared"), patch: ["title": .string("Pending")])
    try await library.loadLocal()
    #expect(library.randomizerCandidates(mode: .diamond, verticals: verticals).first?.title
      == "Pending")
    let another = try localFeatureLibrary(userID: "another-account")
    try await seed([.diamond(featureProject("shared", title: "Other account", status: "progress",
      user: "another-account"))], library: another)
    let firstModel = LibraryRandomizer(library: library)
    let secondModel = LibraryRandomizer(library: another)
    let first = try #require(firstModel.beginSelection(mode: .diamond, verticals: verticals))
    let second = try #require(secondModel.beginSelection(mode: .diamond, verticals: verticals))
    firstModel.finishSelection(id: second)
    #expect(firstModel.isSelecting)
    firstModel.finishSelection(id: first)
    #expect(firstModel.currentWinner(verticals: verticals)?.title == "Pending")
    #expect(secondModel.selection?.winner.title == "Other account")
  }

  @Test func candidateProjectionRefreshesAfterLocalWritesAndReloads() async throws {
    let library = try localFeatureLibrary()
    try await seed([
      .diamond(featureProject("project", title: "Original", status: "progress")),
      .book(featureBook("book", title: "Original book", status: "in_progress")),
      .page(featurePage("page", book: "book", number: 1, status: "in_progress")),
    ], library: library)
    #expect(library.randomizerCandidates(mode: .diamond, verticals: verticals).first?.title
      == "Original")
    #expect(library.randomizerCandidates(mode: .page, verticals: verticals).first?.bookTitle
      == "Original book")

    let _: DiamondProjectRecord = try await library.update(collection: "projects",
      id: "project", body: ["title": "Edited", "status": "kitted"])
    #expect(library.randomizerCandidates(mode: .diamond, verticals: verticals).isEmpty)
    #expect(library.randomizerCandidates(mode: .diamond, statuses: ["kitted"],
      verticals: verticals).first?.title == "Edited")
    #expect(library.randomizerTarget(id: LocalRecordKey(kind: .project, id: "project"),
      mode: .diamond, verticals: verticals)?.title == "Edited")

    let _: ColoringBookRecord = try await library.update(collection: "coloring_books",
      id: "book", body: ["title": "Renamed book"])
    #expect(library.randomizerCandidates(mode: .page, verticals: verticals).first?.bookTitle
      == "Renamed book")
    try await library.store.removeConfirmed(scope: library.scope,
      key: LocalRecordKey(kind: .page, id: "page"))
    try await library.loadLocal()
    #expect(library.randomizerCandidates(mode: .page, verticals: verticals).isEmpty)
    try await library.close(removingData: false)
    for mode in RandomizerMode.allCases {
      #expect(library.randomizerCandidates(mode: mode, verticals: verticals).isEmpty)
      #expect(library.ownedRandomizerCandidates(mode: mode).isEmpty)
    }
  }

  @Test func cancelledWorkCannotStartOrFinishSelection() async throws {
    let library = try localFeatureLibrary()
    try await seed([.diamond(featureProject("only", title: "Only", status: "progress"))],
      library: library)
    let model = LibraryRandomizer(library: library)
    let spin = try #require(model.beginSelection(mode: .diamond, verticals: verticals))
    await Task { @MainActor in
      withUnsafeCurrentTask { $0?.cancel() }
      model.finishSelection(id: spin)
    }.value
    #expect(model.isSelecting)
    model.reset()
    let cancelledResult = await Task { @MainActor in
      withUnsafeCurrentTask { $0?.cancel() }
      return model.beginSelection(mode: .diamond, verticals: verticals)
    }.value
    #expect(cancelledResult == nil)
    #expect(model.selection == nil)
    #expect(!model.isSelecting)
  }

  @Test func repeatedSpinsUseFullPoolAndAllowImmediateRepeats() async throws {
    let library = try localFeatureLibrary()
    try await seed([
      .diamond(featureProject("first", title: "First", status: "progress")),
      .diamond(featureProject("second", title: "Second", status: "progress")),
    ], library: library)
    let model = LibraryRandomizer(library: library)
    var generator = FixedRandomGenerator()
    var previous: LocalRecordKey?
    for _ in 0..<3 {
      let spin = try #require(model.beginSelection(mode: .diamond, verticals: verticals,
        using: &generator))
      let selection = try #require(model.selection)
      let geometry = try #require(model.wheelSpin)
      #expect(selection.candidates.count == 2)
      if let previous { #expect(selection.winner.id == previous) }
      #expect(selection.candidates[try #require(RandomizerWheelGeometry.indexUnderPointer(
        rotation: geometry.endRotation, count: geometry.count))].id == selection.winner.id)
      previous = selection.winner.id
      model.finishSelection(id: spin)
    }
  }

  private struct FixedRandomGenerator: RandomNumberGenerator {
    mutating func next() -> UInt64 { 0 }
  }

  @Test func closedSessionCannotCompleteOrPublishOldSpin() async throws {
    let library = try localFeatureLibrary()
    try await seed([.diamond(featureProject("only", title: "Only", status: "progress"))],
      library: library)
    let model = LibraryRandomizer(library: library)
    let spin = try #require(model.beginSelection(mode: .diamond, verticals: verticals))
    let frozen = model.selection
    try await library.close(removingData: false)
    model.finishSelection(id: spin)
    #expect(model.isSelecting)
    #expect(model.selection == frozen)
    #expect(model.currentWinner(verticals: verticals) == nil)
    model.reset()
    #expect(model.beginSelection(mode: .diamond, verticals: verticals) == nil)
    #expect(model.wheelSpin == nil)
  }

  @Test func resetCancelsWheelWithoutChangingSupersedingWinner() async throws {
    let library = try localFeatureLibrary()
    try await seed([.diamond(featureProject("only", title: "Only", status: "progress"))],
      library: library)
    let model = LibraryRandomizer(library: library)
    let old = try #require(model.beginSelection(mode: .diamond, verticals: verticals))
    model.reset()
    #expect(model.wheelRotation == 0)
    #expect(model.wheelSpin == nil)
    let current = try #require(model.beginSelection(mode: .diamond, verticals: verticals))
    let frozen = model.selection
    model.finishSelection(id: old)
    #expect(model.isSelecting)
    #expect(model.selection == frozen)
    model.finishSelection(id: current)
    #expect(model.currentWinner(verticals: verticals)?.recordID == "only")
    #expect(model.wheelSpin?.winnerIndex == 0)
    #expect(RandomizerWheelGeometry.indexUnderPointer(rotation: model.wheelRotation, count: 1) == 0)
  }

  @Test func wheelOrderMatchesWebActivityAndUpdateSorts() async throws {
    let library = try localFeatureLibrary()
    var recentActivity = featureBook("a", title: "Recent activity", status: "in_progress")
    recentActivity.lastActivityAt = "2026-10-09"
    var olderActivity = featureBook("b", title: "Older activity", status: "in_progress")
    olderActivity.lastActivityAt = "2026-10-01"
    try await seed([
      .diamond(featureProject("a", title: "Older", status: "progress", updated: "2026-10-01")),
      .diamond(featureProject("b", title: "Newer", status: "progress", updated: "2026-10-09")),
      .book(olderActivity), .book(recentActivity),
    ], library: library)
    #expect(library.randomizerCandidates(mode: .diamond, verticals: verticals).map(\.item.recordID)
      == ["b", "a"])
    #expect(library.randomizerCandidates(mode: .book, verticals: verticals).map(\.item.recordID)
      == ["a", "b"])
    let stored: ColoringBookRecord = try library.record(collection: "coloring_books", id: "a")
    #expect(stored.lastActivityAt == "2026-10-09")
    #expect(stored.withExpand(nil).lastActivityAt == stored.lastActivityAt)
    #expect(try JSONDecoder().decode(ColoringBookRecord.self,
      from: JSONEncoder().encode(featureBook("legacy", title: "Legacy"))).lastActivityAt == nil)
  }

  @Test func completionYieldsOneFrozenDrawForRecording() async throws {
    let library = try localFeatureLibrary()
    try await seed([.diamond(featureProject("only", title: "Only", status: "progress"))],
      library: library)
    let model = LibraryRandomizer(library: library)
    let id = try #require(model.beginSelection(mode: .diamond, verticals: verticals))
    let completed = model.finishSelection(id: id)
    #expect(completed == model.selection)
    #expect(completed?.winner.item.recordID == "only")
    #expect(model.finishSelection(id: id) == nil)
    model.reset()
    #expect(model.finishSelection(id: id) == nil)
  }

}
