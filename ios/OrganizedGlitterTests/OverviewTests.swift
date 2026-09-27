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

  @Test func artworkUsesTheFileAccessBoundary() throws {
    let client = client()
    let library = LibrarySession(
      client: client, userID: "fictional-user", store: try LocalLibraryStore.inMemory())
    let model = OverviewModel(library: library)
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
@Suite("Overview local snapshot")
struct OverviewLoadingTests {
  @Test func shelvesUseLocalRecordsAndStayAvailableOffline() async throws {
    let library = try localFeatureLibrary()
    let active = featureProject("active", title: "Active", status: "progress")
    let kitted = featureProject("kitted", title: "Kitted", status: "kitted")
    try await library.store.ingest(.diamond(active), scope: library.scope)
    try await library.store.ingest(.diamond(kitted), scope: library.scope)
    let model = OverviewModel(library: library)
    await model.load()
    #expect(model.hasLoaded)
    #expect(model.items.map(\.recordID) == ["active"])
    #expect(model.upNext.map(\.recordID) == ["kitted"])
    #expect(model.errorMessage == nil)
  }

  @Test func reloadReflectsLocalRecordChanges() async throws {
    let library = try localFeatureLibrary()
    let project = featureProject("project", title: "Active", status: "progress")
    try await library.store.ingest(.diamond(project), scope: library.scope)
    let model = OverviewModel(library: library)
    await model.load()
    #expect(model.items.count == 1)
    try await library.store.ingest(
      .diamond(featureProject("project", title: "Kitted", status: "kitted")),
      scope: library.scope)
    await model.load()
    #expect(model.items.isEmpty)
    #expect(model.upNext.map(\.recordID) == ["project"])
  }
}
