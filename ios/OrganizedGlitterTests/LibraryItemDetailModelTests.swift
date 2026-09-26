import Foundation
import Testing

@testable import OrganizedGlitter

@MainActor
@Suite(.serialized)
struct LibraryItemDetailModelTests {
  @Test
  func bookPagesAreUserScopedFilteredAndPaginated() async throws {
    let client = try await signedInClient { request in
      let components = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)
      let path = try #require(request.url?.path)
      if path.hasSuffix("/coloring_books/records/book-1") {
        return (200, Self.bookJSON)
      }
      if path.hasSuffix("/coloring_pages/records") {
        let page = components?.queryItems?.first(where: { $0.name == "page" })?.value
        let filter = components?.queryItems?.first(where: { $0.name == "filter" })?.value ?? ""
        #expect(filter.contains(#"book = "book-1""#))
        #expect(filter.contains(#"book.user = "user-1""#))
        if filter.contains(#"status = "completed""#) {
          return (200, Self.pageListJSON(id: "page-3", number: 3, totalPages: 1))
        }
        return page == "2"
          ? (200, Self.pageListJSON(id: "page-2", number: 2, page: 2, totalPages: 2))
          : (200, Self.pageListJSON(id: "page-1", number: 1, page: 1, totalPages: 2))
      }
      Issue.record("Unexpected request: \(request)")
      return (500, "{}")
    }
    let model = LibraryItemDetailModel(
      item: .book(Self.book), client: client, userID: "user-1")

    await model.load()
    #expect(model.bookPages.map(\.id) == ["page-1"])
    #expect(model.canLoadMoreBookPages)

    await model.loadMoreBookPages()
    #expect(model.bookPages.map(\.id) == ["page-1", "page-2"])
    #expect(!model.canLoadMoreBookPages)

    await model.setBookPageFilter(.completed)
    #expect(model.bookPages.map(\.id) == ["page-3"])
  }

  @Test
  func pagePhotoUploadUsesTheAppendFieldAndRefreshesTheRecord() async throws {
    let client = try await signedInClient { request in
      let path = try #require(request.url?.path)
      if request.httpMethod == "PATCH", path.hasSuffix("/coloring_pages/records/page-1") {
        let body = String(decoding: DetailURLProtocol.bodyData(for: request), as: UTF8.self)
        #expect(body.contains("name=\"photos+\""))
        #expect(body.contains("filename=\"artwork.jpg\""))
        return (200, Self.pageJSON(id: "page-1", number: 1, photos: ["artwork.jpg"]))
      }
      if request.httpMethod == "GET", path.hasSuffix("/coloring_pages/records/page-1") {
        return (200, Self.pageJSON(id: "page-1", number: 1, photos: ["artwork.jpg"]))
      }
      Issue.record("Unexpected request: \(request)")
      return (500, "{}")
    }
    let model = LibraryItemDetailModel(
      item: .page(Self.page), client: client, userID: "user-1")
    let photo = ProcessedDetailPhoto(
      data: Data([0xff, 0xd8, 0xff]),
      fileName: "artwork.jpg",
      contentType: "image/jpeg"
    )

    #expect(await model.appendPagePhoto(photo))
    guard case .page(let page) = model.item else {
      Issue.record("Expected a page after upload")
      return
    }
    #expect(page.photos == ["artwork.jpg"])
  }

  @Test
  func diamondProgressPhotoCreatesADatedProjectNote() async throws {
    let client = try await signedInClient { request in
      let path = try #require(request.url?.path)
      if request.httpMethod == "POST", path.hasSuffix("/progress_notes/records") {
        let body = String(decoding: DetailURLProtocol.bodyData(for: request), as: UTF8.self)
        #expect(body.contains("name=\"project\"\r\n\r\nproject-1"))
        #expect(body.contains("name=\"content\"\r\n\r\nHalfway done"))
        #expect(body.contains("name=\"date\"\r\n\r\n2026-09-19"))
        #expect(body.contains("name=\"image\""))
        return (200, Self.noteJSON)
      }
      if path.hasSuffix("/projects/records/project-1") {
        return (200, Self.projectJSON)
      }
      if path.hasSuffix("/progress_notes/records") {
        return (200, Self.noteListJSON)
      }
      Issue.record("Unexpected request: \(request)")
      return (500, "{}")
    }
    let model = LibraryItemDetailModel(
      item: .diamond(Self.project), client: client, userID: "user-1")
    let photo = ProcessedDetailPhoto(
      data: Data([0x89, 0x50, 0x4e, 0x47]),
      fileName: "progress.png",
      contentType: "image/png"
    )
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 19)))

    #expect(
      await model.addDiamondProgressNote(
        content: "Halfway done", date: date, photo: photo
      ))
    #expect(model.progressNotes.map(\.id) == ["note-1"])
  }

  @Test
  func unresolvedPageUploadNeverRepeatsTheWriteWhenRefreshFails() async throws {
    let client = try await signedInClient { request in
      let path = try #require(request.url?.path)
      if request.httpMethod == "PATCH", path.hasSuffix("/coloring_pages/records/page-1") {
        return (500, "{}")
      }
      if request.httpMethod == "GET", path.hasSuffix("/coloring_pages/records/page-1") {
        return (500, "{}")
      }
      Issue.record("Unexpected request: \(request)")
      return (500, "{}")
    }
    let model = LibraryItemDetailModel(
      item: .page(Self.page), client: client, userID: "user-1")
    let photo = ProcessedDetailPhoto(
      data: Data([0xff, 0xd8, 0xff]),
      fileName: "artwork.jpg",
      contentType: "image/jpeg"
    )

    #expect(!(await model.appendPagePhoto(photo)))
    #expect(model.unresolvedWriteState == .needsRefresh)
    #expect(model.mutationErrorMessage?.contains("could not be refreshed") == true)

    #expect(!(await model.appendPagePhoto(photo)))
    #expect(!(await model.refreshUnresolvedWriteStatus()))
    let detailRequests = DetailURLProtocol.requests.dropFirst()
    #expect(detailRequests.map(\.httpMethod) == ["PATCH", "GET", "GET"])
    #expect(detailRequests.filter { $0.httpMethod == "PATCH" }.count == 1)
  }

  @Test
  func cancelledPageUploadEntersUnresolvedWriteRecovery() async throws {
    let client = try await signedInClient { request in
      let path = try #require(request.url?.path)
      if request.httpMethod == "PATCH", path.hasSuffix("/coloring_pages/records/page-1") {
        throw URLError(.cancelled)
      }
      if request.httpMethod == "GET", path.hasSuffix("/coloring_pages/records/page-1") {
        return (200, Self.pageJSON(id: "page-1", number: 1, photos: ["artwork.jpg"]))
      }
      Issue.record("Unexpected request: \(request)")
      return (500, "{}")
    }
    let model = LibraryItemDetailModel(
      item: .page(Self.page), client: client, userID: "user-1")
    let photo = ProcessedDetailPhoto(
      data: Data([0xff, 0xd8, 0xff]),
      fileName: "artwork.jpg",
      contentType: "image/jpeg"
    )

    #expect(!(await model.appendPagePhoto(photo)))
    #expect(model.unresolvedWriteState == .refreshed)
    #expect(!(await model.appendPagePhoto(photo)))
    let patchCount = DetailURLProtocol.requests.filter { $0.httpMethod == "PATCH" }.count
    #expect(patchCount == 1)
  }

  @Test
  func returningToABookKeepsAlreadyLoadedPages() async throws {
    let client = try await signedInClient { request in
      let components = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)
      let path = try #require(request.url?.path)
      if path.hasSuffix("/coloring_books/records/book-1") {
        return (200, Self.bookJSON)
      }
      if path.hasSuffix("/coloring_pages/records") {
        let page = components?.queryItems?.first(where: { $0.name == "page" })?.value
        let perPage = components?.queryItems?.first(where: { $0.name == "perPage" })?.value
        if page == "2" {
          return (200, Self.pageListJSON(id: "page-2", number: 2, page: 2, totalPages: 2))
        }
        if perPage == "2" {
          return (
            200,
            #"{"page":1,"perPage":2,"totalItems":2,"totalPages":1,"items":[\#(Self.pageJSON(id: "page-1", number: 1, photos: [])),\#(Self.pageJSON(id: "page-2", number: 2, photos: []))]}"#
          )
        }
        return (200, Self.pageListJSON(id: "page-1", number: 1, page: 1, totalPages: 2))
      }
      Issue.record("Unexpected request: \(request)")
      return (500, "{}")
    }
    let model = LibraryItemDetailModel(
      item: .book(Self.book), client: client, userID: "user-1")

    await model.load()
    await model.loadMoreBookPages()
    #expect(model.bookPages.map(\.id) == ["page-1", "page-2"])

    await model.load(preservingLoadedBookPages: true)
    #expect(model.bookPages.map(\.id) == ["page-1", "page-2"])
  }

  @Test
  func reloadingMultipleBookPagesKeepsLoadMoreOffset() async throws {
    let client = try await signedInClient { request in
      let path = try #require(request.url?.path)
      if path.hasSuffix("/coloring_books/records/book-1") {
        return (200, Self.bookJSON)
      }
      if path.hasSuffix("/coloring_pages/records") {
        let components = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)
        let query = components?.queryItems ?? []
        let page = try #require(Int(query.first { $0.name == "page" }?.value ?? ""))
        let perPage = try #require(Int(query.first { $0.name == "perPage" }?.value ?? ""))
        let first = (page - 1) * perPage + 1
        let last = min(page * perPage, 60)
        let items = (first...last).map {
          Self.pageJSON(id: "page-\($0)", number: $0, photos: [])
        }.joined(separator: ",")
        return (
          200,
          """
          {"page":\(page),"perPage":\(perPage),"totalItems":60,"totalPages":\((60 + perPage - 1) / perPage),"items":[\(items)]}
          """
        )
      }
      Issue.record("Unexpected request: \(request)")
      return (500, "{}")
    }
    let model = LibraryItemDetailModel(
      item: .book(Self.book), client: client, userID: "user-1")

    await model.load()
    await model.loadMoreBookPages()
    #expect(model.bookPages.count == 48)

    await model.load(preservingLoadedBookPages: true)
    await model.loadMoreBookPages()

    let ids = model.bookPages.map(\.id)
    #expect(ids.count == 60)
    #expect(Set(ids).count == ids.count)
    #expect(ids == (1...60).map { "page-\($0)" })
  }

  @Test
  func confirmedBackdatedDiamondNoteKeepsServerSortWhenRefreshFails() async throws {
    let client = try await signedInClient { request in
      let path = try #require(request.url?.path)
      if request.httpMethod == "GET", path.hasSuffix("/projects/records/project-1") {
        return (200, Self.projectJSON)
      }
      if request.httpMethod == "GET", path.hasSuffix("/progress_notes/records") {
        return (200, Self.newerNoteListJSON)
      }
      Issue.record("Unexpected request: \(request)")
      return (500, "{}")
    }
    let model = LibraryItemDetailModel(
      item: .diamond(Self.project), client: client, userID: "user-1")
    let photo = ProcessedDetailPhoto(
      data: Data([0x89, 0x50, 0x4e, 0x47]),
      fileName: "progress.png",
      contentType: "image/png"
    )

    #expect(await model.load())
    #expect(model.progressNotes.map(\.id) == ["note-new"])

    DetailURLProtocol.handler = { request in
      let path = try #require(request.url?.path)
      if request.httpMethod == "POST", path.hasSuffix("/progress_notes/records") {
        return (200, Self.noteJSON)
      }
      if request.httpMethod == "GET",
        path.hasSuffix("/projects/records/project-1")
          || path.hasSuffix("/progress_notes/records")
      {
        return (500, "{}")
      }
      Issue.record("Unexpected request: \(request)")
      return (500, "{}")
    }

    #expect(
      await model.addDiamondProgressNote(
        content: "Halfway done", date: Date(timeIntervalSince1970: 0), photo: photo
      ))
    #expect(model.progressNotes.map(\.id) == ["note-new", "note-1"])
    #expect(model.errorMessage != nil)
  }

  @Test
  func uncertainTextOnlyDiamondNotePointsToProgressNotes() async throws {
    let client = try await signedInClient { request in
      let path = try #require(request.url?.path)
      if request.httpMethod == "POST", path.hasSuffix("/progress_notes/records") {
        return (500, "{}")
      }
      if request.httpMethod == "GET", path.hasSuffix("/projects/records/project-1") {
        return (200, Self.projectJSON)
      }
      if request.httpMethod == "GET", path.hasSuffix("/progress_notes/records") {
        return (200, Self.textOnlyNoteListJSON)
      }
      Issue.record("Unexpected request: \(request)")
      return (500, "{}")
    }
    let model = LibraryItemDetailModel(
      item: .diamond(Self.project), client: client, userID: "user-1")

    #expect(
      !(await model.addDiamondProgressNote(
        content: "Reached the halfway point", date: Date(timeIntervalSince1970: 0), photo: nil
      )))
    #expect(model.unresolvedWriteState == .refreshed)
    #expect(model.mutationErrorMessage?.contains("progress notes") == true)
    #expect(model.mutationErrorMessage?.contains("photos") == false)
    let progressNoteWrites = DetailURLProtocol.requests.filter {
      $0.httpMethod == "POST"
        && $0.url?.path.hasSuffix("/progress_notes/records") == true
    }
    #expect(progressNoteWrites.count == 1)
  }

  @Test
  func failedBookFilterClearsPagesThatBelongToThePreviousFilter() async throws {
    let client = try await signedInClient { request in
      let components = URLComponents(
        url: try #require(request.url), resolvingAgainstBaseURL: false)
      let path = try #require(request.url?.path)
      if path.hasSuffix("/coloring_books/records/book-1") {
        return (200, Self.bookJSON)
      }
      if path.hasSuffix("/coloring_pages/records") {
        let filter = components?.queryItems?.first(where: { $0.name == "filter" })?.value ?? ""
        if filter.contains(#"status = "completed""#) {
          return (500, "{}")
        }
        return (200, Self.pageListJSON(id: "page-1", number: 1, totalPages: 1))
      }
      Issue.record("Unexpected request: \(request)")
      return (500, "{}")
    }
    let model = LibraryItemDetailModel(
      item: .book(Self.book), client: client, userID: "user-1")

    await model.load()
    #expect(model.bookPages.map(\.id) == ["page-1"])
    await model.setBookPageFilter(.completed)

    #expect(model.bookPageFilter == .completed)
    #expect(model.bookPages.isEmpty)
    #expect(model.errorMessage != nil)
  }

  private func signedInClient(
    handler: @escaping @Sendable (URLRequest) throws -> (Int, String)
  ) async throws -> PocketBaseClient {
    DetailURLProtocol.requests = []
    DetailURLProtocol.handler = { request in
      if request.url?.path.hasSuffix("/users/auth-with-password") == true {
        return (
          200,
          #"{"token":"token-1","record":{"id":"user-1","email":"test@example.test","verified":true}}"#
        )
      }
      return try handler(request)
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DetailURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://detail.example.test")!,
      sessionStore: KeychainSessionStore(
        service: "com.interactivebuffoonery.organizedglitter.detail-tests.\(UUID().uuidString)"
      ),
      urlSession: URLSession(configuration: configuration)
    )
    _ = try await client.signIn(identity: "test@example.test", password: "password")
    return client
  }

  nonisolated private static let book = ColoringBookRecord(
    id: "book-1", user: "user-1", title: "Forest Walk", series: nil,
    status: "in_progress", totalPages: 12, completedPages: 2,
    completionPercentage: 16.7, coverImage: nil, publisher: nil,
    illustrator: nil, created: "2026-01-01", updated: "2026-01-02", expand: nil)

  nonisolated private static let page = ColoringPageRecord(
    id: "page-1", book: "book-1", pageNumber: 1, status: "in_progress",
    photos: [], revealedSubject: nil, completedAt: nil, startedAt: "2026-01-02",
    created: "2026-01-01", updated: "2026-01-02", expand: nil)

  nonisolated private static let project = DiamondProjectRecord(
    id: "project-1", title: "Moon Garden", user: "user-1", company: nil,
    artist: nil, status: "progress", kitCategory: "full", drillShape: "round",
    generalNotes: nil, width: 40, height: 50, image: nil, dateStarted: nil,
    dateCompleted: nil, created: "2026-01-01", updated: "2026-01-02", expand: nil)

  nonisolated private static let bookJSON =
    #"{"id":"book-1","user":"user-1","title":"Forest Walk","status":"in_progress","total_pages":12,"completed_pages":2,"completion_percentage":16.7,"photos":[],"created":"2026-01-01","updated":"2026-01-02"}"#

  nonisolated private static let projectJSON =
    #"{"id":"project-1","title":"Moon Garden","user":"user-1","status":"progress","kit_category":"full","drill_shape":"round","width":40,"height":50,"created":"2026-01-01","updated":"2026-01-02"}"#

  nonisolated private static let noteJSON =
    #"{"id":"note-1","project":"project-1","content":"Halfway done","date":"2026-09-19 00:00:00.000Z","image":"progress.png","created":"2026-09-19","updated":"2026-09-19"}"#

  nonisolated private static let noteListJSON =
    #"{"page":1,"perPage":20,"totalItems":1,"totalPages":1,"items":[{"id":"note-1","project":"project-1","content":"Halfway done","date":"2026-09-19 00:00:00.000Z","image":"progress.png","created":"2026-09-19","updated":"2026-09-19"}]}"#

  nonisolated private static let newerNoteListJSON =
    #"{"page":1,"perPage":20,"totalItems":1,"totalPages":1,"items":[{"id":"note-new","project":"project-1","content":"Latest update","date":"2026-09-20 00:00:00.000Z","created":"2026-09-20","updated":"2026-09-20"}]}"#

  nonisolated private static let textOnlyNoteListJSON =
    #"{"page":1,"perPage":20,"totalItems":1,"totalPages":1,"items":[{"id":"note-text","project":"project-1","content":"Reached the halfway point","date":"2026-09-19 00:00:00.000Z","created":"2026-09-19","updated":"2026-09-19"}]}"#

  nonisolated private static func pageListJSON(
    id: String,
    number: Int,
    page: Int = 1,
    totalPages: Int
  ) -> String {
    """
    {"page":\(page),"perPage":24,"totalItems":\(totalPages),"totalPages":\(totalPages),"items":[\(pageJSON(id: id, number: number, photos: []))]}
    """
  }

  nonisolated private static func pageJSON(
    id: String,
    number: Int,
    photos: [String]
  ) -> String {
    let encodedPhotos = photos.map { #""\#($0)""# }.joined(separator: ",")
    return """
      {"id":"\(id)","book":"book-1","page_number":\(number),"status":"in_progress","photos":[\(encodedPhotos)],"created":"2026-01-01","updated":"2026-01-02"}
      """
  }
}

private final class DetailURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, String))?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    do {
      Self.requests.append(request)
      let handler = Self.handler ?? { _ in (500, "{}") }
      let (status, body) = try handler(request)
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(body.utf8))
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}

  nonisolated(unsafe) static var requests: [URLRequest] = []

  nonisolated static func bodyData(for request: URLRequest) -> Data {
    if let body = request.httpBody {
      return body
    }
    guard let stream = request.httpBodyStream else {
      return Data()
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while true {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else {
        return data
      }
      data.append(buffer, count: count)
    }
  }
}
