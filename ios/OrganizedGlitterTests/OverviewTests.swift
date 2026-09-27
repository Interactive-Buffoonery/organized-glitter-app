import Foundation
import Testing

@testable import OrganizedGlitter

@MainActor
@Suite("Overview month boundary")
struct OverviewTests {
  /// A timestamp just after midnight UTC on the first of the month. Before the
  /// fix the boundary was built from the local calendar but serialized as UTC,
  /// so in any negative-offset zone this instant fell outside "this month".
  @Test("month start is the first of the month as a PocketBase date")
  func monthStartIsFirstOfMonth() throws {
    let july = try #require(
      ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z")
    )

    #expect(OverviewModel.startOfMonth(containing: july, timeZone: .gmt) == "2026-07-01")
  }

  @Test("month end is the exclusive first day of the next month")
  func monthEndIsExclusive() throws {
    let july = try #require(
      ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z")
    )

    #expect(OverviewModel.startOfNextMonth(containing: july, timeZone: .gmt) == "2026-08-01")
  }

  @Test("boundary rolls to the correct month across a year boundary")
  func januaryBoundary() throws {
    let december = try #require(
      ISO8601DateFormatter().date(from: "2026-12-05T08:00:00Z")
    )

    #expect(OverviewModel.startOfMonth(containing: december, timeZone: .gmt) == "2026-12-01")
    #expect(OverviewModel.startOfNextMonth(containing: december, timeZone: .gmt) == "2027-01-01")
  }

  @Test("this month uses the local calendar, not the UTC month")
  func localEveningStaysInTheLocalMonth() throws {
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let localEvening = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 20))
    )

    #expect(OverviewModel.startOfMonth(containing: localEvening, timeZone: timeZone) == "2026-10-01")
    #expect(
      OverviewModel.startOfNextMonth(containing: localEvening, timeZone: timeZone) == "2026-11-01")
    #expect(OverviewModel.startOfMonth(containing: localEvening, timeZone: .gmt) == "2026-11-01")
  }
}

@MainActor
@Suite("Overview presentation behavior")
struct OverviewPresentationTests {
  private func client() -> PocketBaseClient {
    PocketBaseClient(
      baseURL: URL(string: "https://overview.example.invalid")!,
      sessionStore: KeychainSessionStore(service: "OverviewTests.\(UUID().uuidString)")
    )
  }

  private func project(image: String? = nil) -> LibraryItem {
    .diamond(
      DiamondProjectRecord(
        id: "fictional-project", title: "Garden of stars", user: "fictional-user",
        company: nil, artist: nil, status: "progress", kitCategory: "full",
        drillShape: nil, generalNotes: nil, width: nil, height: nil, image: image,
        dateStarted: nil, dateCompleted: nil, created: "2026-09-01", updated: "2026-09-07",
        expand: nil
      ))
  }

  private func page(photos: [String] = []) -> LibraryItem {
    .page(
      ColoringPageRecord(
        id: "fictional-page", book: "fictional-book", pageNumber: 12,
        status: "in_progress", photos: photos, revealedSubject: "A moonlit garden",
        completedAt: nil, startedAt: nil, created: "2026-09-01", updated: "2026-09-06",
        expand: nil
      ))
  }

  @Test func continueOrdersByLatestNoteThenUpdated() {
    let noted = project()
    let recent = page()
    // The page was updated later, but the project was logged the same day.
    #expect(
      OverviewModel.continueOrder([recent, noted], latestNoteDates: ["fictional-project": "2026-09-06 00:00:00.000Z"])
        == [noted, recent])
    #expect(OverviewModel.continueOrder([noted, recent], latestNoteDates: [:]) == [noted, recent])
    #expect(
      OverviewModel.continueOrder([noted, recent], latestNoteDates: ["fictional-page": "2026-09-01"])
        == [noted, recent])
  }

  @Test func loggedCaptionIsRelativeForAWeek() throws {
    let zone = try #require(TimeZone(identifier: "America/New_York"))
    // 2026-09-20 23:30 in New York, already the 21st in UTC.
    let now = try #require(ISO8601DateFormatter().date(from: "2026-09-21T03:30:00Z"))
    #expect(OverviewModel.loggedCaption(noteDate: "2026-09-20", now: now, timeZone: zone) == "Logged today")
    #expect(OverviewModel.loggedCaption(noteDate: "2026-09-19 00:00:00.000Z", now: now, timeZone: zone) == "Logged yesterday")
    #expect(OverviewModel.loggedCaption(noteDate: "2026-09-15", now: now, timeZone: zone) == "Logged 5 days ago")
    #expect(OverviewModel.loggedCaption(noteDate: "2026-09-13", now: now, timeZone: zone)?.hasPrefix("Logged Sep") == true)
    #expect(OverviewModel.loggedCaption(noteDate: "not a date", now: now, timeZone: zone) == nil)
  }

  @Test func artworkUsesTheFileAccessBoundary() {
    let client = client()
    let model = OverviewModel(client: client, userID: "fictional-user")
    #expect(
      model.artworkURL(for: project(image: "garden image.png"), token: "file-token")
        == client.fileURL(
          collection: "projects", recordID: "fictional-project", filename: "garden image.png",
          thumb: ArtworkThumb.gallery, token: "file-token"
        ))
    #expect(
      model.artworkURL(for: page(photos: ["", "page.png", "later.png"]), token: "file-token")
        == client.fileURL(
          collection: "coloring_pages", recordID: "fictional-page", filename: "page.png",
          thumb: ArtworkThumb.gallery, token: "file-token"
        ))
    #expect(model.artworkURL(for: project(), token: "file-token") == nil)
    #expect(model.artworkURL(for: project(image: ""), token: "file-token") == nil)
    #expect(model.artworkURL(for: page(), token: "file-token") == nil)
    #expect(model.artworkURL(for: page(photos: [""]), token: "file-token") == nil)
    #expect(model.artworkURL(for: project(image: "garden image.png"), token: nil) == nil)
  }
}

@MainActor
@Suite("Overview loading", .serialized)
struct OverviewLoadingTests {
  private func model() async throws -> OverviewModel {
    OverviewURLProtocol.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OverviewURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://overview.example.invalid")!,
      sessionStore: KeychainSessionStore(service: "OverviewLoadingTests.\(UUID().uuidString)"),
      urlSession: URLSession(configuration: configuration)
    )
    _ = try await client.signIn(identity: "fictional-user", password: "example-password")
    return OverviewModel(client: client, userID: "fictional-user")
  }

  private func waitForFirstNoteRequest() async -> Bool {
    await waitForSignal(OverviewURLProtocol.firstNoteStarted)
  }

  private func waitForFirstActiveRequest() async -> Bool {
    await waitForSignal(OverviewURLProtocol.firstActiveStarted)
  }

  private func waitForSignal(_ signal: DispatchSemaphore) async -> Bool {
    await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        continuation.resume(returning: signal.wait(timeout: .now() + 2) == .success)
      }
    }
  }

  @Test func shelvesAppearBeforeOptionalNoteDatesReturn() async throws {
    let model = try await model()

    await model.load()

    #expect(model.hasLoaded)
    #expect(!model.isLoading)
    #expect(model.items.map(\.recordID) == ["project-1"])
    #expect(model.completedThisMonthCount == 5)
    #expect(model.latestNoteDates.isEmpty)
    #expect(await waitForFirstNoteRequest())

    OverviewURLProtocol.firstNoteGate.signal()
    await model.noteDatesTask?.value
    #expect(model.latestNoteDates == ["project-1": "2026-09-20"])
  }

  @Test func supersededNoteDatesCannotReplaceReloadedShelves() async throws {
    let model = try await model()
    await model.load()
    #expect(await waitForFirstNoteRequest())
    let oldDatesTask = model.noteDatesTask

    await model.load()
    await model.noteDatesTask?.value
    OverviewURLProtocol.firstNoteGate.signal()
    await oldDatesTask?.value

    #expect(model.items.map(\.recordID) == ["project-2"])
    #expect(model.latestNoteDates == ["project-2": "2026-09-21"])
  }

  @Test func cancelledNoteDatesDoNotEnrichTheShelf() async throws {
    let model = try await model()
    await model.load()
    #expect(await waitForFirstNoteRequest())

    model.cancelNoteDates()
    OverviewURLProtocol.firstNoteGate.signal()
    await model.noteDatesTask?.value

    #expect(model.items.map(\.recordID) == ["project-1"])
    #expect(model.latestNoteDates.isEmpty)
  }

  @Test func supersededListErrorDoesNotReplaceReloadedShelf() async throws {
    let model = try await model()
    OverviewURLProtocol.delayFirstActiveFailure = true
    let firstLoad = Task { await model.load() }
    #expect(await waitForFirstActiveRequest())

    await model.load()
    OverviewURLProtocol.firstActiveGate.signal()
    await firstLoad.value
    await model.noteDatesTask?.value

    #expect(model.items.map(\.recordID) == ["project-2"])
    #expect(model.errorMessage == nil)
  }

  @Test func supersededUnauthorizedListCannotExpireSession() async throws {
    let model = try await model()
    let expirations = OverviewExpirationCounter()
    model.onSessionExpired = { expirations.count += 1 }
    OverviewURLProtocol.delayFirstActiveFailure = true
    OverviewURLProtocol.firstActiveFailureStatus = 401
    let firstLoad = Task { await model.load() }
    #expect(await waitForFirstActiveRequest())

    await model.load()
    OverviewURLProtocol.firstActiveGate.signal()
    await firstLoad.value
    await model.noteDatesTask?.value

    #expect(model.items.map(\.recordID) == ["project-3"])
    #expect(model.errorMessage == nil)
    #expect(expirations.count == 0)
  }
}

@MainActor
private final class OverviewExpirationCounter {
  var count = 0
}

private final class OverviewURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var firstNoteGate = DispatchSemaphore(value: 0)
  nonisolated(unsafe) static var firstNoteStarted = DispatchSemaphore(value: 0)
  nonisolated(unsafe) static var firstActiveGate = DispatchSemaphore(value: 0)
  nonisolated(unsafe) static var firstActiveStarted = DispatchSemaphore(value: 0)
  nonisolated(unsafe) static var delayFirstActiveFailure = false
  nonisolated(unsafe) static var firstActiveFailureStatus = 500
  nonisolated(unsafe) static var activeListCount = 0
  private static let stateLock = NSLock()

  private let requestLock = NSLock()
  private var cancelled = false
  private var waitingForNote = false
  private var waitingForActive = false

  static func reset() {
    stateLock.lock()
    activeListCount = 0
    firstNoteGate = DispatchSemaphore(value: 0)
    firstNoteStarted = DispatchSemaphore(value: 0)
    firstActiveGate = DispatchSemaphore(value: 0)
    firstActiveStarted = DispatchSemaphore(value: 0)
    delayFirstActiveFailure = false
    firstActiveFailureStatus = 500
    stateLock.unlock()
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path ?? ""
    if path == "/api/notes/latest" {
      Self.stateLock.lock()
      let isFirstLoad = Self.activeListCount == 1
      Self.stateLock.unlock()
      if isFirstLoad {
        requestLock.lock()
        waitingForNote = true
        requestLock.unlock()
        Self.firstNoteStarted.signal()
        DispatchQueue.global().async {
          Self.firstNoteGate.wait()
          self.respond(#"{"items":[{"targetId":"project-1","date":"2026-09-20"}]}"#)
        }
      } else {
        respond(#"{"items":[{"targetId":"project-2","date":"2026-09-21"}]}"#)
      }
      return
    }

    if path == "/api/collections/users/auth-with-password" {
      respond(#"{"token":"example-token","record":{"id":"fictional-user","verified":true}}"#)
      return
    }
    if path == "/api/collections/users/auth-refresh" {
      respond(#"{"token":"refreshed-token","record":{"id":"fictional-user","verified":true}}"#)
      return
    }

    let filter = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
      .queryItems?.first(where: { $0.name == "filter" })?.value ?? ""
    if path.contains("/projects/") && filter.contains(#"status = "progress""#) {
      Self.stateLock.lock()
      Self.activeListCount += 1
      let number = Self.activeListCount
      let delayedFailure = number == 1 && Self.delayFirstActiveFailure
      let retryFailure = number == 2 && Self.delayFirstActiveFailure
        && Self.firstActiveFailureStatus == 401
      let failureStatus = Self.firstActiveFailureStatus
      Self.stateLock.unlock()
      if delayedFailure {
        requestLock.lock()
        waitingForActive = true
        requestLock.unlock()
        Self.firstActiveStarted.signal()
        DispatchQueue.global().async {
          Self.firstActiveGate.wait()
          self.respond("{}", status: failureStatus)
        }
      } else if retryFailure {
        respond("{}", status: 401)
      } else {
        respond(list(
          items: """
            {"id":"project-\(number)","title":"Example \(number)","user":"fictional-user","status":"progress","kit_category":"full","created":"2026-09-01","updated":"2026-09-0\(number)"}
            """, total: 1))
      }
    } else if path.contains("/projects/") && filter.contains(#"status = "completed""#) {
      respond(list(items: "", total: 2))
    } else if path.contains("/coloring_pages/") && filter.contains(#"status = "completed""#) {
      respond(list(items: "", total: 3))
    } else {
      respond(list(items: "", total: 0))
    }
  }

  override func stopLoading() {
    requestLock.lock()
    cancelled = true
    let unblockNote = waitingForNote
    let unblockActive = waitingForActive
    requestLock.unlock()
    if unblockNote { Self.firstNoteGate.signal() }
    if unblockActive { Self.firstActiveGate.signal() }
  }

  private func list(items: String, total: Int) -> String {
    """
    {"page":1,"perPage":10,"totalItems":\(total),"totalPages":1,"items":[\(items)]}
    """
  }

  private func respond(_ body: String, status: Int = 200) {
    requestLock.lock()
    let shouldRespond = !cancelled
    requestLock.unlock()
    guard shouldRespond, let url = request.url else { return }
    let response = HTTPURLResponse(
      url: url, statusCode: status, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
}
