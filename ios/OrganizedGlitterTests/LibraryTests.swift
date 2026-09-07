import Foundation
import Testing

@testable import OrganizedGlitter

@MainActor
struct LibraryTests {
  @Test
  func repeatingWishlistHandoffReloadsTheUnsearchedListing() async throws {
    let wishlist = projectList(["Moon Garden", "Star Quilt"], status: "wishlist")
    let searched = projectList(["Moon Garden"], status: "wishlist")
    let client = try await signedInClient(
      responses: [
        (200, wishlist),
        (200, searched),
        (200, wishlist),
      ])
    let model = LibraryModel(client: client, userID: "user-1")
    var listingIdentity = model.listingIdentity

    model.apply(LibraryRequest(section: .diamonds, status: "wishlist"))
    await loadIfListingChanged(model, token: &listingIdentity)

    #expect(model.projects.map(\.title) == ["Moon Garden", "Star Quilt"])
    #expect(
      filter(from: LibraryURLProtocol.requests.last) == #"user = "user-1" && status = "wishlist""#)

    model.searchText = "Moon"
    await model.load()
    #expect(model.projects.map(\.title) == ["Moon Garden"])
    #expect(
      filter(from: LibraryURLProtocol.requests.last)
        == #"user = "user-1" && (title ~ "Moon" || artist.name ~ "Moon" || company.name ~ "Moon") && status = "wishlist""#)

    model.apply(LibraryRequest(section: .diamonds, status: "wishlist"))
    await loadIfListingChanged(model, token: &listingIdentity)

    #expect(model.searchText.isEmpty)
    #expect(model.projects.map(\.title) == ["Moon Garden", "Star Quilt"])
    #expect(
      filter(from: LibraryURLProtocol.requests.last) == #"user = "user-1" && status = "wishlist""#)
    #expect(LibraryURLProtocol.requests.count == 4)
  }

  @Test
  func loadsAdditionalPagesWithoutReplacingEarlierItems() async throws {
    let client = try await signedInClient(
      responses: [
        (200, projectList(["Moon Garden", "Star Quilt"], page: 1, totalPages: 2, totalItems: 3)),
        (
          200,
          projectList(
            ["River Path"], page: 2, totalPages: 2, totalItems: 3, idOffset: 2)
        ),
      ])
    let model = LibraryModel(client: client, userID: "user-1")
    await model.load()
    #expect(model.projects.map(\.title) == ["Moon Garden", "Star Quilt"])
    #expect(model.canLoadMore)
    #expect(query(from: LibraryURLProtocol.requests.last, name: "page") == "1")

    await model.load(reset: false)
    #expect(model.projects.map(\.title) == ["Moon Garden", "Star Quilt", "River Path"])
    #expect(!model.canLoadMore)
    #expect(query(from: LibraryURLProtocol.requests.last, name: "page") == "2")
  }

  @Test
  func delayedResponsesDoNotReplaceANewerCraftListing() async throws {
    let client = try await signedInClient(
      responses: [
        (200, projectList(["Moon Garden"]), 0.2),
        (200, bookList(["Quiet pages"]), 0),
      ])
    let model = LibraryModel(client: client, userID: "user-1")
    let diamonds = Task { await model.load() }
    try await Task.sleep(for: .milliseconds(40))
    model.select(.books)
    await model.load()
    await diamonds.value

    #expect(model.section == .books)
    #expect(model.books.map(\.title) == ["Quiet pages"])
    #expect(model.projects.isEmpty)
    #expect(model.items.map(\.title) == ["Quiet pages"])
  }

  @Test
  func delayedResponsesDoNotReplaceANewerStatusFilter() async throws {
    let client = try await signedInClient(
      responses: [
        (200, projectList(["Moon Garden"], status: "wishlist"), 0.2),
        (200, projectList(["Star Quilt"], status: "progress"), 0),
      ])
    let model = LibraryModel(client: client, userID: "user-1")
    model.statusFilter = "wishlist"
    let wishlist = Task { await model.load() }
    try await Task.sleep(for: .milliseconds(40))
    model.statusFilter = "progress"
    await model.load()
    await wishlist.value

    #expect(model.statusFilter == "progress")
    #expect(model.projects.map(\.title) == ["Star Quilt"])
    #expect(
      filter(from: LibraryURLProtocol.requests.last) == #"user = "user-1" && status = "progress""#)
  }

  @Test
  func artworkUsesTheFileAccessBoundaryForEveryCraft() {
    let client = PocketBaseClient(
      baseURL: URL(string: "https://library.example.test")!,
      sessionStore: KeychainSessionStore(
        service: "LibraryArtwork.\(UUID().uuidString)")
    )
    let diamond = LibraryItem.diamond(
      DiamondProjectRecord(
        id: "project-1", title: "Moon Garden", user: "user-1", company: nil,
        artist: nil, status: "wishlist", kitCategory: "full", drillShape: nil,
        generalNotes: nil, width: nil, height: nil, image: "garden.png",
        dateStarted: nil, dateCompleted: nil, created: "2026-01-01",
        updated: "2026-01-02", expand: nil))
    let book = LibraryItem.book(
      ColoringBookRecord(
        id: "book-1", user: "user-1", title: "Quiet pages", series: nil,
        status: "wishlist", totalPages: 12, completedPages: nil,
        completionPercentage: nil, coverImage: "cover.png", publisher: nil,
        illustrator: nil, created: "2026-01-01", updated: "2026-01-02",
        expand: nil))
    let page = LibraryItem.page(
      ColoringPageRecord(
        id: "page-1", book: "book-1", pageNumber: 3, status: "not_started",
        photos: ["", "page.png"], revealedSubject: nil, completedAt: nil,
        startedAt: nil, created: "2026-01-01", updated: "2026-01-02",
        expand: nil))

    #expect(
      diamond.artworkURL(using: client)
        == client.fileURL(collection: "projects", recordID: "project-1", filename: "garden.png"))
    #expect(
      book.artworkURL(using: client)
        == client.fileURL(
          collection: "coloring_books", recordID: "book-1", filename: "cover.png"))
    #expect(
      page.artworkURL(using: client)
        == client.fileURL(
          collection: "coloring_pages", recordID: "page-1", filename: "page.png"))
    #expect(
      LibraryItem.diamond(
        DiamondProjectRecord(
          id: "project-1", title: "Moon Garden", user: "user-1", company: nil,
          artist: nil, status: "wishlist", kitCategory: "full", drillShape: nil,
          generalNotes: nil, width: nil, height: nil, image: "",
          dateStarted: nil, dateCompleted: nil, created: "2026-01-01",
          updated: "2026-01-02", expand: nil)
      ).artworkURL(using: client) == nil)
    #expect(diamond.artworkAccessibilityLabel == "Project photo")
    #expect(book.artworkAccessibilityLabel == "Book cover")
    #expect(page.artworkAccessibilityLabel == "Page photo")
  }

  @Test
  func savedSelectionClearsWhenStatusNoLongerMatchesTheFilter() async throws {
    let client = try await signedInClient(
      responses: [
        (200, projectList(["Moon Garden"], status: "wishlist")),
        (200, projectList([], status: "wishlist")),
      ])
    let model = LibraryModel(client: client, userID: "user-1")
    model.statusFilter = "wishlist"
    await model.load()
    #expect(model.projects.map(\.title) == ["Moon Garden"])

    let saved = LibraryItem.diamond(
      DiamondProjectRecord(
        id: "project-1", title: "Moon Garden", user: "user-1", company: nil,
        artist: nil, status: "progress", kitCategory: "full", drillShape: nil,
        generalNotes: nil, width: nil, height: nil, image: nil,
        dateStarted: nil, dateCompleted: nil, created: "2026-01-01",
        updated: "2026-01-03", expand: nil))

    let selection = await model.selection(afterSaving: saved)

    #expect(selection == nil)
    #expect(model.projects.isEmpty)
    #expect(
      filter(from: LibraryURLProtocol.requests.last) == #"user = "user-1" && status = "wishlist""#)
  }

  @Test
  func savedSelectionKeepsAnUpdatedRecordMissingFromTheFirstPage() async throws {
    let client = try await signedInClient(
      responses: [
        (
          200,
          projectList(
            ["Moon Garden", "Star Quilt"], page: 1, totalPages: 2, totalItems: 3)
        ),
        (
          200,
          projectList(
            ["River Path"], page: 2, totalPages: 2, totalItems: 3, idOffset: 2)
        ),
        (
          200,
          projectList(
            ["Moon Garden", "Star Quilt"], page: 1, totalPages: 2, totalItems: 3)
        ),
      ])
    let model = LibraryModel(client: client, userID: "user-1")
    await model.load()
    await model.load(reset: false)
    #expect(model.projects.map(\.title) == ["Moon Garden", "Star Quilt", "River Path"])

    let saved = LibraryItem.diamond(
      DiamondProjectRecord(
        id: "project-3", title: "River Path Revised", user: "user-1", company: nil,
        artist: nil, status: "progress", kitCategory: "full", drillShape: nil,
        generalNotes: nil, width: nil, height: nil, image: nil,
        dateStarted: nil, dateCompleted: nil, created: "2026-01-01",
        updated: "2026-01-04", expand: nil))

    let selection = await model.selection(afterSaving: saved)

    #expect(selection?.title == "River Path Revised")
    #expect(selection?.id == "diamond:project-3")
    #expect(model.projects.map(\.title) == ["Moon Garden", "Star Quilt"])
    #expect(query(from: LibraryURLProtocol.requests.last, name: "page") == "1")
  }

  @Test
  func savedPageSelectionKeepsTheParentBookWhenMissingFromTheFirstPage() async throws {
    let client = try await signedInClient(
      responses: [
        (200, pageList([(1, "Quiet pages")], page: 1, totalPages: 2, totalItems: 2)),
        (200, pageList([(12, "Quiet pages")], page: 2, totalPages: 2, totalItems: 2, idOffset: 1)),
        (200, pageList([(1, "Quiet pages")], page: 1, totalPages: 2, totalItems: 2)),
      ])
    let model = LibraryModel(client: client, userID: "user-1")
    model.select(.pages)
    await model.load()
    await model.load(reset: false)
    #expect(model.pages.map(\.pageNumber) == [1, 12])

    let saved = LibraryItem.page(
      ColoringPageRecord(
        id: "page-2", book: "book-1", pageNumber: 12, status: "in_progress",
        photos: [], revealedSubject: "A moonlit garden", completedAt: nil,
        startedAt: nil, created: "2026-01-01", updated: "2026-01-04",
        expand: nil))

    let selection = await model.selection(afterSaving: saved)

    #expect(selection?.id == "page:page-2")
    #expect(selection?.title == "A moonlit garden")
    #expect(selection?.libraryCaption == "Quiet pages")
    #expect(model.pages.map(\.pageNumber) == [1])
  }

  @Test
  func savedPageSelectionStaysWhenBookSearchCannotSeeTheSaveExpand() async throws {
    let client = try await signedInClient(
      responses: [
        (200, pageList([(1, "Quiet pages")], page: 1, totalPages: 2, totalItems: 2)),
        (200, pageList([(12, "Quiet pages")], page: 2, totalPages: 2, totalItems: 2, idOffset: 1)),
        (200, pageList([(1, "Quiet pages")], page: 1, totalPages: 2, totalItems: 2)),
      ])
    let model = LibraryModel(client: client, userID: "user-1")
    model.select(.pages)
    model.searchText = "Quiet pages"
    await model.load()
    await model.load(reset: false)

    let saved = LibraryItem.page(
      ColoringPageRecord(
        id: "page-2", book: "book-1", pageNumber: 12, status: "not_started",
        photos: [], revealedSubject: "A moonlit garden", completedAt: nil,
        startedAt: nil, created: "2026-01-01", updated: "2026-01-04",
        expand: nil))

    let selection = await model.selection(afterSaving: saved)

    #expect(selection?.id == "page:page-2")
    #expect(selection?.libraryCaption == "Quiet pages")
    #expect(
      filter(from: LibraryURLProtocol.requests.last)
        == #"book.user = "user-1" && book.title ~ "Quiet pages""#)
  }

  @Test
  func diamondSearchMatchesTitleArtistAndCompany() async throws {
    let client = try await signedInClient(responses: [(200, projectList(["Moon Garden"]))])
    let model = LibraryModel(client: client, userID: "user-1")
    model.searchText = "atelier"
    await model.load()

    #expect(
      filter(from: LibraryURLProtocol.requests.last)
        == #"user = "user-1" && (title ~ "atelier" || artist.name ~ "atelier" || company.name ~ "atelier")"#)
  }

  @Test
  func bookSearchMatchesTitlePublisherAndIllustrator() async throws {
    let client = try await signedInClient(responses: [(200, bookList(["Quiet pages"]))])
    let model = LibraryModel(client: client, userID: "user-1")
    model.select(.books)
    model.searchText = "Press"
    await model.load()

    #expect(
      filter(from: LibraryURLProtocol.requests.last)
        == #"user = "user-1" && (title ~ "Press" || publisher.name ~ "Press" || illustrator.name ~ "Press")"#)
  }

  @Test
  func savedSelectionKeepsACreditMatchMissingFromTheFirstPage() async throws {
    let client = try await signedInClient(
      responses: [
        (200, projectList(["Moon Garden"], page: 1, totalPages: 2, totalItems: 2)),
        (
          200,
          projectList(
            ["River Path"], page: 2, totalPages: 2, totalItems: 2, idOffset: 1,
            company: "Fictional atelier")
        ),
        (200, projectList(["Moon Garden"], page: 1, totalPages: 2, totalItems: 2)),
      ])
    let model = LibraryModel(client: client, userID: "user-1")
    model.searchText = "atelier"
    await model.load()
    await model.load(reset: false)

    let saved = LibraryItem.diamond(
      DiamondProjectRecord(
        id: "project-2", title: "River Path Revised", user: "user-1", company: nil,
        artist: nil, status: "progress", kitCategory: "full", drillShape: nil,
        generalNotes: nil, width: nil, height: nil, image: nil,
        dateStarted: nil, dateCompleted: nil, created: "2026-01-01",
        updated: "2026-01-04", expand: nil))

    let selection = await model.selection(afterSaving: saved)

    #expect(selection?.title == "River Path Revised")
    #expect(selection?.libraryCaption == "Fictional atelier")
  }

  @Test
  func alignUsesTheFirstEnabledCraftOnColoringOnlyAccounts() {
    let model = LibraryModel(
      client: PocketBaseClient(
        baseURL: URL(string: "https://library.example.test")!,
        sessionStore: KeychainSessionStore(
          service: "LibraryAlign.\(UUID().uuidString)")
      ),
      userID: "user-1"
    )
    #expect(model.section == .diamonds)

    model.align(
      to: VerticalPreferences(diamondPainting: false, coloringBooks: true))

    #expect(model.section == .books)
    #expect(model.statusFilter == nil)
  }

  @Test
  func deleteRemovesTheRecordFromVisibleResults() async throws {
    let client = try await signedInClient(
      responses: [
        (200, projectList(["Moon Garden", "Star Quilt"])),
        (204, ""),
        (200, projectList(["Star Quilt"], idOffset: 1)),
      ])
    let model = LibraryModel(client: client, userID: "user-1")
    await model.load()
    let doomed = try #require(model.items.first)

    await model.delete(doomed)

    #expect(model.projects.map(\.title) == ["Star Quilt"])
    #expect(!model.items.contains(where: { $0.id == doomed.id }))
    #expect(LibraryURLProtocol.requests.map(\.httpMethod) == ["POST", "GET", "DELETE", "GET"])
  }

  @Test
  func galleryCaptionsPreferCompanyPublisherAndParentBook() {
    let diamond = LibraryItem.diamond(
      DiamondProjectRecord(
        id: "project-1", title: "Moon Garden", user: "user-1", company: nil,
        artist: nil, status: "progress", kitCategory: "full", drillShape: nil,
        generalNotes: nil, width: nil, height: nil, image: nil,
        dateStarted: nil, dateCompleted: nil, created: "2026-01-01",
        updated: "2026-01-02",
        expand: DiamondProjectExpand(
          company: NamedRelationRecord(id: "c1", name: "Fictional atelier"),
          artist: NamedRelationRecord(id: "a1", name: "A. Artist"))))
    let book = LibraryItem.book(
      ColoringBookRecord(
        id: "book-1", user: "user-1", title: "Quiet pages", series: "Meadows",
        status: "in_progress", totalPages: 12, completedPages: 2,
        completionPercentage: nil, coverImage: nil, publisher: nil,
        illustrator: nil, created: "2026-01-01", updated: "2026-01-02",
        expand: ColoringBookExpand(
          publisher: NamedRelationRecord(id: "p1", name: "Fictional Press"),
          illustrator: nil)))
    let page = LibraryItem.page(
      ColoringPageRecord(
        id: "page-1", book: "book-1", pageNumber: 3, status: "not_started",
        photos: [], revealedSubject: "An empty page", completedAt: nil,
        startedAt: nil, created: "2026-01-01", updated: "2026-01-02",
        expand: ColoringPageExpand(
          book: ColoringBookRecord(
            id: "book-1", user: "user-1", title: "Quiet pages", series: nil,
            status: "in_progress", totalPages: 12, completedPages: nil,
            completionPercentage: nil, coverImage: nil, publisher: nil,
            illustrator: nil, created: "2026-01-01", updated: "2026-01-02",
            expand: nil))))

    #expect(diamond.libraryCaption == "Fictional atelier")
    #expect(book.libraryCaption == "Fictional Press")
    #expect(page.libraryCaption == "Quiet pages")
  }

  private func loadIfListingChanged(_ model: LibraryModel, token: inout String) async {
    let next = model.listingIdentity
    guard next != token else {
      return
    }
    token = next
    await model.load()
  }

  private func filter(from request: URLRequest?) -> String {
    query(from: request, name: "filter") ?? ""
  }

  private func query(from request: URLRequest?, name: String) -> String? {
    URLComponents(url: request?.url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)?
      .queryItems?.first(where: { $0.name == name })?.value
  }

  private func projectList(
    _ titles: [String],
    status: String = "progress",
    page: Int = 1,
    totalPages: Int = 1,
    totalItems: Int? = nil,
    idOffset: Int = 0,
    company: String? = nil
  ) -> String {
    let items = titles.enumerated().map { index, title in
      let expand: String
      if let company {
        expand =
          #","expand":{"company":{"id":"c1","name":"\#(company)"},"artist":null}"#
      } else {
        expand = ""
      }
      return """
        {"id":"project-\(idOffset + index + 1)","title":"\(title)","user":"user-1","status":"\(status)","kit_category":"full","created":"2026-01-01 00:00:00.000Z","updated":"2026-01-0\(index + 2) 00:00:00.000Z"\(expand)}
        """
    }.joined(separator: ",")
    return """
      {"page":\(page),"perPage":50,"totalItems":\(totalItems ?? titles.count),"totalPages":\(totalPages),"items":[\(items)]}
      """
  }

  private func pageList(
    _ entries: [(number: Int, bookTitle: String)],
    status: String = "not_started",
    page: Int = 1,
    totalPages: Int = 1,
    totalItems: Int? = nil,
    idOffset: Int = 0
  ) -> String {
    let items = entries.enumerated().map { index, entry in
      """
      {"id":"page-\(idOffset + index + 1)","book":"book-1","page_number":\(entry.number),"status":"\(status)","photos":[],"created":"2026-01-01 00:00:00.000Z","updated":"2026-01-0\(index + 2) 00:00:00.000Z","expand":{"book":{"id":"book-1","user":"user-1","title":"\(entry.bookTitle)","status":"in_progress","total_pages":12,"created":"2026-01-01 00:00:00.000Z","updated":"2026-01-02 00:00:00.000Z"}}}
      """
    }.joined(separator: ",")
    return """
      {"page":\(page),"perPage":50,"totalItems":\(totalItems ?? entries.count),"totalPages":\(totalPages),"items":[\(items)]}
      """
  }

  private func bookList(_ titles: [String]) -> String {
    let items = titles.enumerated().map { index, title in
      """
      {"id":"book-\(index + 1)","user":"user-1","title":"\(title)","status":"in_stash","total_pages":12,"created":"2026-01-01 00:00:00.000Z","updated":"2026-01-02 00:00:00.000Z"}
      """
    }.joined(separator: ",")
    return """
      {"page":1,"perPage":50,"totalItems":\(titles.count),"totalPages":1,"items":[\(items)]}
      """
  }

  private func signedInClient(responses: [(Int, String)]) async throws -> PocketBaseClient {
    try await signedInClient(responses: responses.map { ($0.0, $0.1, 0) })
  }

  private func signedInClient(responses: [(Int, String, TimeInterval)]) async throws
    -> PocketBaseClient
  {
    LibraryURLProtocol.requests = []
    LibraryURLProtocol.responses = [
      (
        200,
        #"{"token":"token-1","record":{"id":"user-1","email":"sarah@example.test","verified":true}}"#,
        0
      )
    ] + responses
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LibraryURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://library.example.test")!,
      sessionStore: KeychainSessionStore(
        service: "com.interactivebuffoonery.organizedglitter.tests.\(UUID().uuidString)"),
      urlSession: URLSession(configuration: configuration)
    )
    _ = try await client.signIn(identity: "sarah@example.test", password: "password")
    return client
  }
}

private final class LibraryURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var requests: [URLRequest] = []
  nonisolated(unsafe) static var responses: [(Int, String, TimeInterval)] = []

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.requests.append(request)
    let (status, body, delay) = Self.responses.removeFirst()
    if delay > 0 {
      Thread.sleep(forTimeInterval: delay)
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
