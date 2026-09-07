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

    #expect(OverviewModel.startOfMonth(containing: july) == "2026-07-01")
  }

  @Test("month end is the exclusive first day of the next month")
  func monthEndIsExclusive() throws {
    let july = try #require(
      ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z")
    )

    #expect(OverviewModel.startOfNextMonth(containing: july) == "2026-08-01")
  }

  @Test("boundary rolls to the correct month across a year boundary")
  func januaryBoundary() throws {
    let december = try #require(
      ISO8601DateFormatter().date(from: "2026-12-05T08:00:00Z")
    )

    #expect(OverviewModel.startOfMonth(containing: december) == "2026-12-01")
    #expect(OverviewModel.startOfNextMonth(containing: december) == "2027-01-01")
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

  @Test func artworkUsesTheFileAccessBoundary() {
    let client = client()
    let model = OverviewModel(client: client, userID: "fictional-user")
    #expect(
      model.artworkURL(for: project(image: "garden image.png"))
        == client.fileURL(
          collection: "projects", recordID: "fictional-project", filename: "garden image.png"
        ))
    #expect(
      model.artworkURL(for: page(photos: ["", "page.png", "later.png"]))
        == client.fileURL(
          collection: "coloring_pages", recordID: "fictional-page", filename: "page.png"
        ))
    #expect(model.artworkURL(for: project()) == nil)
    #expect(model.artworkURL(for: project(image: "")) == nil)
    #expect(model.artworkURL(for: page()) == nil)
    #expect(model.artworkURL(for: page(photos: [""])) == nil)
  }

  @Test func wishlistNavigationClearsAnExistingSearchAndFilter() {
    let model = LibraryModel(client: client(), userID: "fictional-user")
    model.select(.pages)
    model.searchText = "previous search"
    model.statusFilter = "completed"
    let request = LibraryRequest(section: .books, status: "wishlist")
    model.apply(request)
    #expect(model.section == .books)
    #expect(model.searchText.isEmpty)
    #expect(model.statusFilter == "wishlist")

    model.searchText = "another search"
    model.apply(LibraryRequest(section: .books, status: "wishlist"))
    #expect(model.searchText.isEmpty)
    #expect(request != LibraryRequest(section: .books, status: "wishlist"))
  }
}
