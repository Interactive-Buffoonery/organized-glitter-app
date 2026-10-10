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

  @Test func defaultsUseRawStatusesForEachMode() async throws {
    let library = try localFeatureLibrary()
    try await seed([
      .diamond(featureProject("active", title: "Active", status: "progress")),
      .diamond(featureProject("label", title: "Label", status: "In progress")),
      .diamond(featureProject("stash", title: "Stash", status: "stash")),
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
    #expect(library.randomizerCandidates(mode: .diamond, statuses: ["stash"],
      verticals: verticals).map(\.item.recordID) == ["stash"])
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


  @Test func pickAgainExcludesPreviousWhenAlternativesExist() async throws {
    let library = try localFeatureLibrary()
    try await seed([
      .diamond(featureProject("first", title: "First", status: "progress")),
      .diamond(featureProject("second", title: "Second", status: "progress")),
    ], library: library)
    let model = LibraryRandomizer(library: library)
    var previous: LocalRecordKey?
    for _ in 0..<8 {
      let spin = try #require(model.beginSelection(mode: .diamond, verticals: verticals))
      let selection = try #require(model.selection)
      #expect(selection.candidates.count == 2)
      #expect(selection.winner.id != previous)
      previous = selection.winner.id
      model.finishSelection(id: spin)
    }
    let spin = try #require(model.beginSelection(mode: .diamond, selectedIDs: [previous!],
      verticals: verticals))
    #expect(model.selection?.winner.id == previous)
    model.finishSelection(id: spin)
  }

}
