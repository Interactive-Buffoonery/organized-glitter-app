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

  @Test func craftFilterPreservesRecordIdentityAndOrder() {
    let items = [project(), page()]
    #expect(items.filter(OverviewCraft.all.includes) == items)
    #expect(items.filter(OverviewCraft.diamonds.includes) == [items[0]])
    #expect(items.filter(OverviewCraft.coloring.includes) == [items[1]])
    #expect([items[0]].filter(OverviewCraft.coloring.includes).isEmpty)
  }

  @Test func completedShortcutsFollowCraftAndEnabledPreferences() {
    let both = VerticalPreferences(diamondPainting: true, coloringBooks: true)
    let diamondsOnly = VerticalPreferences(diamondPainting: true, coloringBooks: false)
    let coloringOnly = VerticalPreferences(diamondPainting: false, coloringBooks: true)

    #expect(OverviewCraft.all.completedSections(for: both) == [.diamonds, .pages])
    #expect(OverviewCraft.diamonds.completedSections(for: both) == [.diamonds])
    #expect(OverviewCraft.coloring.completedSections(for: both) == [.pages])
    #expect(OverviewCraft.all.completedSections(for: diamondsOnly) == [.diamonds])
    #expect(OverviewCraft.all.completedSections(for: coloringOnly) == [.pages])
    #expect(OverviewCraft.coloring.completedSections(for: diamondsOnly).isEmpty)
    #expect(OverviewCraft.diamonds.completedSections(for: coloringOnly).isEmpty)
  }

  @Test func inProgressShortcutsFollowCraftAndEnabledPreferences() {
    let both = VerticalPreferences(diamondPainting: true, coloringBooks: true)
    let diamondsOnly = VerticalPreferences(diamondPainting: true, coloringBooks: false)
    let coloringOnly = VerticalPreferences(diamondPainting: false, coloringBooks: true)

    #expect(OverviewCraft.all.inProgressSections(for: both) == [.diamonds, .pages])
    #expect(OverviewCraft.diamonds.inProgressSections(for: both) == [.diamonds])
    #expect(OverviewCraft.coloring.inProgressSections(for: both) == [.pages])
    #expect(OverviewCraft.all.inProgressSections(for: diamondsOnly) == [.diamonds])
    #expect(OverviewCraft.all.inProgressSections(for: coloringOnly) == [.pages])
    #expect(OverviewCraft.coloring.inProgressSections(for: diamondsOnly).isEmpty)
    #expect(OverviewCraft.diamonds.inProgressSections(for: coloringOnly).isEmpty)
    #expect(OverviewCraft.all.inProgressStatus(for: .diamonds) == "progress")
    #expect(OverviewCraft.all.inProgressStatus(for: .pages) == "in_progress")
    #expect(OverviewCraft.all.inProgressStatus(for: .books) == nil)
  }

  @Test func wishlistShortcutsFollowCraftAndEnabledPreferences() {
    let both = VerticalPreferences(diamondPainting: true, coloringBooks: true)
    let diamondsOnly = VerticalPreferences(diamondPainting: true, coloringBooks: false)
    let coloringOnly = VerticalPreferences(diamondPainting: false, coloringBooks: true)

    #expect(OverviewCraft.all.wishlistSections(for: both) == [.diamonds, .books])
    #expect(OverviewCraft.diamonds.wishlistSections(for: both) == [.diamonds])
    #expect(OverviewCraft.coloring.wishlistSections(for: both) == [.books])
    #expect(OverviewCraft.all.wishlistSections(for: diamondsOnly) == [.diamonds])
    #expect(OverviewCraft.all.wishlistSections(for: coloringOnly) == [.books])
    #expect(OverviewCraft.coloring.wishlistSections(for: diamondsOnly).isEmpty)
    #expect(OverviewCraft.diamonds.wishlistSections(for: coloringOnly).isEmpty)
  }

  @Test func artworkUsesTheFileAccessBoundary() {
    let client = client()
    let model = OverviewModel(client: client, userID: "fictional-user")
    #expect(
      model.artworkURL(for: project(image: "garden image.png"), token: "file-token")
        == client.fileURL(
          collection: "projects", recordID: "fictional-project", filename: "garden image.png",
          thumb: ArtworkThumb.compact, token: "file-token"
        ))
    #expect(
      model.artworkURL(for: page(photos: ["", "page.png", "later.png"]), token: "file-token")
        == client.fileURL(
          collection: "coloring_pages", recordID: "fictional-page", filename: "page.png",
          thumb: ArtworkThumb.compact, token: "file-token"
        ))
    #expect(model.artworkURL(for: project(), token: "file-token") == nil)
    #expect(model.artworkURL(for: project(image: ""), token: "file-token") == nil)
    #expect(model.artworkURL(for: page(), token: "file-token") == nil)
    #expect(model.artworkURL(for: page(photos: [""]), token: "file-token") == nil)
    #expect(model.artworkURL(for: project(image: "garden image.png"), token: nil) == nil)
  }
}
