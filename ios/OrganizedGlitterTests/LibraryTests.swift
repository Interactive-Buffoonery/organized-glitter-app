import Foundation
import Testing

@testable import OrganizedGlitter

@MainActor
@Suite(.serialized)
struct LibraryTests {
  @Test func lostDeleteResponseDoesNotClaimDiskReloadIsServerRefresh() async throws {
    LostDeleteURLProtocol.snapshotAvailable = false
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LostDeleteURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://lost-delete.example.test")!,
      sessionStore: KeychainSessionStore(service: "LostDeleteTests.\(UUID().uuidString)"),
      urlSession: URLSession(configuration: configuration))
    await client.prepareOfflineSession(StoredSession(token: "example-token", userID: "feature-user"))
    let library = LibrarySession(
      client: client, userID: "feature-user", store: try LocalLibraryStore.inMemory())
    let project = featureProject("project", title: "Moon Garden")
    try await library.store.ingest(.diamond(project), scope: library.scope)
    let model = LibraryModel(library: library)
    await model.load()

    await model.delete(.diamond(project))
    #expect(model.items.map(\.recordID) == [project.id])
    #expect(model.mutationError?.contains("status is unknown") == true)

    LostDeleteURLProtocol.snapshotAvailable = true
    await model.refresh()
    #expect(model.items.isEmpty)
  }

  @Test func localLibrarySearchesFiltersAndSortsWithoutNetwork() async throws {
    let library = try localFeatureLibrary()
    try await library.store.ingest(.diamond(featureProject("a", title: "Moon Garden", status: "wishlist", updated: "2026-09-02")), scope: library.scope)
    try await library.store.ingest(.diamond(featureProject("b", title: "Star Quilt", status: "progress", updated: "2026-09-03")), scope: library.scope)
    try await library.store.ingest(.diamond(featureProject("c", title: "Moonlight", status: "wishlist", updated: "2026-09-01")), scope: library.scope)
    let model = LibraryModel(library: library)

    await model.load()
    #expect(model.items.map(\.title) == ["Star Quilt", "Moon Garden", "Moonlight"])
    model.searchText = "moon"
    model.statusFilter = "wishlist"
    model.sort = .titleAscending
    await model.load()
    #expect(model.items.map(\.title) == ["Moon Garden", "Moonlight"])
    model.apply(LibraryRequest(section: .diamonds, status: "progress"))
    await model.load()
    #expect(model.items.map(\.title) == ["Star Quilt"])
    #expect(model.committedSearch.isEmpty)
  }

  @Test func browsingAllGroupsActiveShelvesFirst() async throws {
    let library = try localFeatureLibrary()
    try await library.store.ingest(.diamond(featureProject("a", title: "Done", status: "completed", updated: "2026-09-05")), scope: library.scope)
    try await library.store.ingest(.diamond(featureProject("b", title: "Wish", status: "wishlist", updated: "2026-09-04")), scope: library.scope)
    try await library.store.ingest(.diamond(featureProject("c", title: "Older", status: "progress", updated: "2026-09-01")), scope: library.scope)
    try await library.store.ingest(.diamond(featureProject("d", title: "Newer", status: "progress", updated: "2026-09-03")), scope: library.scope)
    let model = LibraryModel(library: library)

    await model.load()
    #expect(model.shelves.map(\.status) == ["progress", "wishlist", "completed"])
    #expect(model.shelves.first?.items.map(\.title) == ["Newer", "Older"])
    #expect(model.shelfCounts["progress"] == 2)
    #expect(library.shelfCounts(for: .diamonds) == ["progress": 2, "wishlist": 1, "completed": 1])
    #expect(library.shelfCounts(for: .books).isEmpty)
    model.statusFilter = "progress"
    await model.load()
    #expect(!model.isShelved)
  }

  @Test func shelfCountsFollowLocalEditsAndSessionClosure() async throws {
    let library = try localFeatureLibrary()
    let project = featureProject("project", title: "Moon Garden", status: "wishlist")
    try await library.store.ingest(.diamond(project), scope: library.scope)
    try await library.loadLocal()
    #expect(library.shelfCounts(for: .diamonds) == ["wishlist": 1])

    let saved: DiamondProjectRecord = try await library.update(
      collection: "projects", id: project.id, body: ["status": "stash"])
    #expect(saved.status == "stash")
    #expect(library.shelfCounts(for: .diamonds) == ["stash": 1])

    try await library.close(removingData: false)
    #expect(library.shelfCounts(for: .diamonds).isEmpty)
    #expect(library.ownedBookTitles().isEmpty)
  }

  @Test func shelfCountsFollowReloadsAndOwnedBookRemoval() async throws {
    let library = try localFeatureLibrary()
    let book = featureBook("book", title: "Quiet Pages")
    let page = featurePage("page", book: book.id, number: 1)
    try await library.store.ingest(.book(book), scope: library.scope)
    try await library.store.ingest(.page(page), scope: library.scope)
    try await library.loadLocal()
    #expect(library.shelfCounts(for: .books) == ["purchased": 1])
    #expect(library.shelfCounts(for: .pages) == ["not_started": 1])
    #expect(library.ownedBookTitles() == [book.id: book.title])

    try await library.store.ingest(
      .page(featurePage(page.id, book: book.id, number: 1, status: "in_progress")),
      scope: library.scope)
    try await library.loadLocal()
    #expect(library.shelfCounts(for: .pages) == ["in_progress": 1])

    try await library.store.removeConfirmed(
      scope: library.scope, key: LibraryItem.book(book).localRecordKey)
    try await library.loadLocal()
    #expect(library.shelfCounts(for: .books).isEmpty)
    #expect(library.shelfCounts(for: .pages).isEmpty)
    #expect(library.ownedBookTitles().isEmpty)
  }

  @Test func localPaginationKeepsEarlierItems() async throws {
    let library = try localFeatureLibrary()
    for index in 0..<35 {
      try await library.store.ingest(
        .diamond(featureProject("project-\(index)", title: "Project \(index)")),
        scope: library.scope)
    }
    let model = LibraryModel(library: library)
    await model.load()
    #expect(model.items.count == 30)
    #expect(model.canLoadMore)
    let firstIDs = model.items.map(\.id)
    await model.load(reset: false)
    #expect(model.items.count == 35)
    #expect(Array(model.items.prefix(30)).map(\.id) == firstIDs)
    #expect(!model.canLoadMore)
  }

  @Test func coloringBrowsesBooksAndSearchesTheirPages() async throws {
    let library = try localFeatureLibrary()
    let book = featureBook("book", title: "Quiet Pages")
    try await library.store.ingest(.book(book), scope: library.scope)
    try await library.store.ingest(.page(featurePage("page", book: book.id, number: 12)), scope: library.scope)
    let browse = LibraryModel(library: library)
    browse.select(.books)
    await browse.load()
    #expect(browse.items.map(\.recordID) == [book.id])
    #expect(browse.shelfCounts == ["purchased": 1])

    let search = LibraryModel(library: library, searchesColoringPages: true)
    search.select(.books)
    search.searchText = "Quiet"
    await search.load()
    #expect(Set(search.items.map(\.recordID)) == ["book", "page"])
    search.searchText = "12"
    await search.load()
    #expect(search.items.map(\.recordID) == ["page"])
  }

  @Test func numericColoringSearchMatchesNumbersTitlesAndSubjects() async throws {
    let library = try localFeatureLibrary()
    try await library.store.ingest(.book(featureBook("year-book", title: "Garden 2026")), scope: library.scope)
    try await library.store.ingest(.book(featureBook("book", title: "Quiet Pages")), scope: library.scope)
    try await library.store.ingest(.page(featurePage("title-match", book: "year-book", number: 1)), scope: library.scope)
    try await library.store.ingest(.page(featurePage("number-match", book: "book", number: 2026)), scope: library.scope)
    let subjectPage = ColoringPageRecord(
      id: "subject-match", book: "book", pageNumber: 2, status: "not_started", photos: [],
      revealedSubject: "2026", completedAt: nil, startedAt: nil,
      created: "2026-09-01", updated: "2026-09-01", expand: nil)
    try await library.store.ingest(.page(subjectPage), scope: library.scope)
    try await library.store.ingest(.page(featurePage("unrelated", book: "book", number: 3)), scope: library.scope)
    let model = LibraryModel(library: library, searchesColoringPages: true)
    model.select(.books)
    model.searchText = "2026"
    await model.load()
    #expect(Set(model.items.map(\.recordID)) == ["year-book", "title-match", "number-match", "subject-match"])
  }

  @Test func pageRequestsRemainReachableThroughSearch() async throws {
    let library = try localFeatureLibrary()
    try await library.store.ingest(.book(featureBook("book", title: "Quiet Pages")), scope: library.scope)
    try await library.store.ingest(.page(featurePage("active", book: "book", number: 1, status: "in_progress")), scope: library.scope)
    try await library.store.ingest(.page(featurePage("waiting", book: "book", number: 2)), scope: library.scope)
    let request = LibraryRequest(section: .pages, status: "in_progress")
    #expect(LibraryPresentation.search.accepts(request))
    #expect(!LibraryPresentation.browse.accepts(request))
    #expect(!LibraryPresentation.craft(.books).accepts(request))
    let model = LibraryModel(library: library, searchesColoringPages: true)
    model.apply(request)
    model.align(to: VerticalPreferences(diamondPainting: true, coloringBooks: true))
    await model.load()
    #expect(model.items.map(\.recordID) == ["active"])
    model.align(to: VerticalPreferences(diamondPainting: true, coloringBooks: false))
    #expect(model.section == .diamonds)
  }

  @Test func pagesSearchByNumberAndBookTitle() async throws {
    let library = try localFeatureLibrary()
    try await library.store.ingest(.book(featureBook("book", title: "Quiet Pages")), scope: library.scope)
    try await library.store.ingest(.page(featurePage("one", book: "book", number: 1)), scope: library.scope)
    try await library.store.ingest(.page(featurePage("twelve", book: "book", number: 12)), scope: library.scope)
    let model = LibraryModel(library: library)
    model.select(.pages)
    model.searchText = "12"
    await model.load()
    #expect(model.items.map(\.recordID) == ["twelve"])
    model.searchText = "quiet"
    await model.load()
    #expect(model.items.count == 2)
    model.sort = .pageDescending
    await model.load()
    #expect(model.items.map(\.recordID) == ["twelve", "one"])
  }

  @Test func savedSelectionLeavesFilteredListingWhenStatusChanges() async throws {
    let library = try localFeatureLibrary()
    let project = featureProject("a", title: "Moon Garden", status: "wishlist")
    try await library.store.ingest(.diamond(project), scope: library.scope)
    let model = LibraryModel(library: library)
    model.statusFilter = "wishlist"
    await model.load()
    let changed = featureProject("a", title: "Moon Garden", status: "progress")
    try await library.store.ingest(.diamond(changed), scope: library.scope)
    #expect(await model.selection(afterSaving: .diamond(changed)) == nil)
  }

  @Test func savedBookRespectsCurrentFilterWithoutReloading() async throws {
    let library = try localFeatureLibrary()
    let book = featureBook("book", title: "Quiet Pages", status: "purchased")
    try await library.store.ingest(.book(book), scope: library.scope)
    let model = LibraryModel(library: library)
    model.select(.books)
    await model.load()

    let changed = featureBook("book", title: "Quiet Pages", status: "completed")
    model.acceptSavedBook(changed)
    #expect(model.items.map(\.status) == ["completed"])

    model.statusFilter = "purchased"
    await model.load()
    model.acceptSavedBook(changed)
    #expect(model.items.isEmpty)
  }

  @Test func pageSearchDoesNotRevealAnotherAccountsBook() async throws {
    let library = try localFeatureLibrary(userID: "another-user")
    await #expect(throws: LocalLibraryError.self) {
      try await library.store.ingest(
        .book(featureBook("book", title: "Private Book")), scope: library.scope)
    }
    await #expect(throws: LocalLibraryError.self) {
      try await library.store.ingest(
        .page(featurePage("page", book: "book", number: 1)), scope: library.scope)
    }
    let model = LibraryModel(library: library)
    model.select(.pages)
    model.searchText = "Private"
    await model.load()
    #expect(model.items.isEmpty)
  }

  @Test func punctuationInSearchIsTreatedAsText() async throws {
    let library = try localFeatureLibrary()
    try await library.store.ingest(
      .diamond(featureProject("one", title: "Garden (2026)")), scope: library.scope)
    try await library.store.ingest(
      .diamond(featureProject("two", title: "Garden 2026")), scope: library.scope)
    let model = LibraryModel(library: library)
    model.searchText = "(2026)"
    await model.load()
    #expect(model.items.map(\.recordID) == ["one"])
  }

  @Test func savedPageContextRequiresTheSameRecordAndBook() {
    let book = featureBook("book", title: "Quiet Pages")
    let prior = featurePage("one", book: book.id, number: 1)
      .withExpand(ColoringPageExpand(book: book))
    let moved = featurePage("one", book: "different", number: 1)
    let other = featurePage("other", book: book.id, number: 1)
    #expect(LibraryItem.page(prior.withExpand(nil))
      .retainingListingContext(from: .page(prior)).libraryCaption == "Quiet Pages")
    #expect(LibraryItem.page(moved)
      .retainingListingContext(from: .page(prior)).libraryCaption.isEmpty)
    #expect(LibraryItem.page(other)
      .retainingListingContext(from: .page(prior)).libraryCaption.isEmpty)
  }

  @Test func galleryCaptionsUseUsefulBrowsingMetadata() {
    let book = featureBook("book", title: "Quiet Pages")
    let page = featurePage("page", book: book.id, number: 3)
      .withExpand(ColoringPageExpand(book: book))
    #expect(LibraryItem.book(book).galleryCaption == "40 pages")
    #expect(LibraryItem.page(page).galleryCaption == "Quiet Pages")
    #expect(LibraryItem.diamond(featureProject("project", title: "Moon")).galleryCaption.isEmpty)
  }
}

private final class LostDeleteURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var snapshotAvailable = false

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard request.url?.path == "/api/mobile/sync/snapshot" else {
      client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
      return
    }
    guard Self.snapshotAvailable else {
      client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
      return
    }
    let body = #"{"version":1,"projects":[],"coloringBooks":[],"coloringPages":[],"progressNotes":[],"coloringPageProgressNotes":[]}"#
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
