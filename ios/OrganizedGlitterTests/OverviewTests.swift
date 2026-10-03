import Foundation
import Testing

@testable import OrganizedGlitter

@MainActor
@Suite("Overview presentation behavior")
struct OverviewPresentationTests {
  private func client() -> PocketBaseClient {
    PocketBaseClient(
      baseURL: URL(string: "https://overview.example.invalid")!,
      sessionStore: KeychainSessionStore(service: "OverviewTests.\(UUID().uuidString)")
    )
  }

  private func project(image: String? = nil, started: String? = nil) -> LibraryItem {
    .diamond(
      DiamondProjectRecord(
        id: "fictional-project", title: "Garden of stars", user: "fictional-user",
        company: nil, artist: nil, status: "progress", kitCategory: "full",
        drillShape: nil, generalNotes: nil, width: nil, height: nil, image: image,
        dateStarted: started, dateCompleted: nil, created: "2026-09-01", updated: "2026-09-07",
        expand: nil
      ))
  }

  private func page(photos: [String] = [], started: String? = nil) -> LibraryItem {
    .page(
      ColoringPageRecord(
        id: "fictional-page", book: "fictional-book", pageNumber: 12,
        status: "in_progress", photos: photos, revealedSubject: "A moonlit garden",
        completedAt: nil, startedAt: started, created: "2026-09-01", updated: "2026-09-06",
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

  @Test func heroIsTheLatestNoteAcrossCrafts() {
    let diamond = project()
    let coloring = page()
    #expect(
      OverviewModel.continueOrder(
        [diamond, coloring],
        latestNoteDates: ["fictional-project": "2026-09-18", "fictional-page": "2026-09-19"]
      ).first == coloring)
    #expect(
      OverviewModel.continueOrder(
        [coloring, diamond],
        latestNoteDates: ["fictional-project": "2026-09-20 00:00:00.000Z", "fictional-page": "2026-09-19"]
      ).first == diamond)
  }

  @Test func heroBreaksSameDayNotesByCreation() {
    let diamond = project()
    let coloring = page()
    let dates = ["fictional-project": "2026-09-19", "fictional-page": "2026-09-19"]
    #expect(
      OverviewModel.continueOrder(
        [diamond, coloring], latestNoteDates: dates,
        noteCreated: ["fictional-project": "2026-09-19 09:00:00.000Z", "fictional-page": "2026-09-19 15:00:00.000Z"]
      ).first == coloring)
    #expect(
      OverviewModel.continueOrder(
        [coloring, diamond], latestNoteDates: dates,
        noteCreated: ["fictional-project": "2026-09-19 18:00:00.000Z", "fictional-page": "2026-09-19 15:00:00.000Z"]
      ).first == diamond)
  }

  @Test func heroFallsBackToTheMostRecentlyStartedItem() {
    // The project was edited more recently, but the page was started later.
    let diamond = project(started: "2026-09-03")
    let coloring = page(started: "2026-09-05 11:00:00.000Z")
    #expect(OverviewModel.continueOrder([diamond, coloring], latestNoteDates: [:]) == [coloring, diamond])
    // Starting something counts as working on it; a same-day note still wins.
    #expect(
      OverviewModel.continueOrder([diamond, coloring], latestNoteDates: ["fictional-project": "2026-09-04"])
        == [coloring, diamond])
    #expect(
      OverviewModel.continueOrder([coloring, diamond], latestNoteDates: ["fictional-project": "2026-09-05"])
        == [diamond, coloring])
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
    #expect(
      project(image: "garden image.png").artworkURL(using: client, thumb: ArtworkThumb.gallery, token: "file-token")
        == client.fileURL(
          collection: "projects", recordID: "fictional-project", filename: "garden image.png",
          thumb: ArtworkThumb.gallery, token: "file-token"
        ))
    #expect(
      page(photos: ["", "page.png", "later.png"]).artworkURL(using: client, thumb: ArtworkThumb.gallery, token: "file-token")
        == client.fileURL(
          collection: "coloring_pages", recordID: "fictional-page", filename: "page.png",
          thumb: ArtworkThumb.gallery, token: "file-token"
        ))
    #expect(project().artworkURL(using: client, thumb: ArtworkThumb.gallery, token: "file-token") == nil)
    #expect(project(image: "").artworkURL(using: client, thumb: ArtworkThumb.gallery, token: "file-token") == nil)
    #expect(page().artworkURL(using: client, thumb: ArtworkThumb.gallery, token: "file-token") == nil)
    #expect(page(photos: [""]).artworkURL(using: client, thumb: ArtworkThumb.gallery, token: "file-token") == nil)
    #expect(project(image: "garden image.png").artworkURL(using: client, thumb: ArtworkThumb.gallery, token: nil) == nil)
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
    #expect(model.errorMessage == nil)
  }

  @Test func heroTakesTheLatestNoteAndItsText() async throws {
    let snapshot = try JSONDecoder().decode(LocalFullSnapshot.self, from: Data(#"""
    {
      "version":1,
      "projects":[
        {"id":"kit","title":"Kit","user":"feature-user","status":"progress","kit_category":"full","created":"2026-09-01","updated":"2026-09-30"}
      ],
      "coloringBooks":[
        {"id":"book","user":"feature-user","title":"Quiet Pages","status":"in_progress","total_pages":8,"created":"2026-09-01","updated":"2026-09-01"}
      ],
      "coloringPages":[
        {"id":"page","book":"book","page_number":3,"status":"in_progress","photos":[],"created":"2026-09-01","updated":"2026-09-01"}
      ],
      "progressNotes":[
        {"id":"kit-note","project":"kit","content":"Corner done","date":"2026-09-18","created":"2026-09-18","updated":"2026-09-18"}
      ],
      "coloringPageProgressNotes":[
        {"id":"page-early","user":"feature-user","page":"page","content":"Earlier","date":"2026-09-19","created":"2026-09-19 08:00:00","updated":"2026-09-19"},
        {"id":"page-late","user":"feature-user","page":"page","content":"Sky blended","date":"2026-09-19","created":"2026-09-19 20:00:00","updated":"2026-09-19"}
      ]
    }
    """#.utf8))
    let library = try localFeatureLibrary()
    try await library.store.ingestSnapshot(snapshot, scope: library.scope)
    let model = OverviewModel(library: library)
    await model.load()
    #expect(model.items.map(\.recordID) == ["page", "kit"])
    #expect(model.latestNoteTexts["page"] == "Sky blended")
    #expect(model.latestNoteTexts["kit"] == "Corner done")
    #expect(model.bookPageCounts["book"] == 8)
  }

  @Test func continueKeepsLatestNoteAndBothCraftQuotas() async throws {
    let library = try localFeatureLibrary()
    let projects = (0..<12).map { index in
      #"{"id":"project-\#(index)","title":"Project \#(index)","user":"feature-user","status":"progress","kit_category":"full","created":"2026-09-01","updated":"2026-09-\#(10 + index)"}"#
    }
    let snapshot = try JSONDecoder().decode(LocalFullSnapshot.self, from: Data(#"""
    {
      "version":1,
      "projects":[\#(projects.joined(separator: ","))],
      "coloringBooks":[],"coloringPages":[],"coloringPageProgressNotes":[],
      "progressNotes":[
        {"id":"note","project":"project-0","content":"Logged","date":"2026-09-25","created":"2026-09-25","updated":"2026-09-25"}
      ]
    }
    """#.utf8))
    try await library.store.ingestSnapshot(snapshot, scope: library.scope)
    try await library.store.ingest(
      .book(featureBook("book", title: "Quiet Pages")), scope: library.scope)
    for index in 0..<12 {
      try await library.store.ingest(
        .page(featurePage("page-\(index)", book: "book", number: index + 1,
          status: "in_progress")), scope: library.scope)
    }
    let model = OverviewModel(library: library)
    await model.load()
    #expect(model.items.count == 20)
    #expect(model.items.filter { if case .diamond = $0 { true } else { false } }.count == 10)
    #expect(model.items.filter { if case .page = $0 { true } else { false } }.count == 10)
    #expect(model.items.first?.recordID == "project-0")
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
  }
}
