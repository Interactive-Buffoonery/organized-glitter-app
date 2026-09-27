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
    #expect(model.items.map(\.id) == [project.id])
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
