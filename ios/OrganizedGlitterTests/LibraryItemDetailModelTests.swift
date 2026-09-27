import Foundation
import Testing

@testable import OrganizedGlitter

@MainActor
struct LibraryItemDetailModelTests {
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
