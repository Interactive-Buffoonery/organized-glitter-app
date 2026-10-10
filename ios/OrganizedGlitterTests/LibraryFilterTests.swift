import Foundation
import Testing

@testable import OrganizedGlitter

@MainActor
struct LibraryFilterTests {
  @Test func diamondDimensionsIntersectAndTagsMatchAnyID() async throws {
    let library = try localFeatureLibrary()
    let first = project("first", company: "company-a", tags: ["tag-a"])
    let second = project("second", company: "company-b", tags: ["tag-b"])
    for record in [first, second] {
      try await library.store.ingest(.diamond(record), scope: library.scope)
    }
    let model = LibraryModel(library: library)
    model.filters = LibraryFilters(companyID: "company-a", artistID: "artist-a",
      drillShape: "round", completionYear: 2025, tagIDs: ["tag-a", "tag-b"])
    await model.load()
    #expect(model.items.map(\.recordID) == ["first"])
    #expect(model.shelves.map(\.status) == ["wishlist"])
    #expect(model.library.shelfCounts(for: .diamonds) == ["wishlist": 2])
    model.filters.artistID = "missing"
    await model.load()
    #expect(model.items.isEmpty)
    #expect(model.filters.artistID == "missing")
    model.resetFilters()
    await model.load()
    #expect(model.items.count == 2)
  }

  @Test func richerFiltersPreserveStatusSearchAndSort() async throws {
    let library = try localFeatureLibrary()
    for record in [project("alpha", company: "company-a"),
      project("zeta", company: "company-a"), project("other", company: "company-b")]
    {
      try await library.store.ingest(.diamond(record), scope: library.scope)
    }
    let model = LibraryModel(library: library)
    model.filters.companyID = "company-a"
    model.sort = .titleDescending
    model.statusFilter = "wishlist"
    await model.load()
    #expect(model.items.map(\.recordID) == ["zeta", "alpha"])
    model.searchText = "alpha"
    await model.load()
    #expect(model.items.map(\.recordID) == ["alpha"])
    model.statusFilter = "progress"
    await model.load()
    #expect(model.items.isEmpty)
    model.resetFilters()
    #expect(model.searchText == "alpha")
    #expect(model.statusFilter == "progress")
    #expect(model.sort == .titleDescending)
  }

  @Test func missingLabelsDoNotPreventFilteringByRelationID() {
    let record = project("one", company: "company-a").withExpand(nil)
    let options = LibraryFilterOptions(items: [.diamond(record)], section: .diamonds,
      userID: "feature-user")
    #expect(options.companies == [LibraryFilterOption(id: "company-a", name: "Unavailable company")])
    #expect(LibraryFilters(companyID: "company-a").matches(.diamond(record)))
    #expect(LibraryFilterOptions(items: [.diamond(record)], section: .books,
      userID: "feature-user").companies.isEmpty)
    #expect(LibraryFilters(tagIDs: ["missing"]).identity != LibraryFilters().identity)
    #expect(LibraryFilters(tagIDs: ["a", "b"]).identity == LibraryFilters(tagIDs: ["b", "a"]).identity)
  }

  @Test func eachDiamondDimensionRequiresItsOwnMatch() {
    let item = LibraryItem.diamond(project("one", company: "company-a", tags: ["tag-a"]))
    #expect(LibraryFilters(companyID: "company-a").matches(item))
    #expect(!LibraryFilters(companyID: "company-b").matches(item))
    #expect(!LibraryFilters(artistID: "artist-b").matches(item))
    #expect(!LibraryFilters(drillShape: "square").matches(item))
    #expect(!LibraryFilters(completionYear: 2026).matches(item))
    #expect(!LibraryFilters(tagIDs: ["tag-b"]).matches(item))
    #expect(LibraryFilters(completionYear: 2025).matches(item))
    #expect(LibraryFilters.year(in: "invalid") == nil)
    #expect(LibraryFilters.year(in: nil) == nil)
  }

  @Test func coloringMatchesAnyIDWithinEachDimension() async throws {
    let library = try localFeatureLibrary()
    for record in [book("first", publisher: "publisher-a", illustrator: "illustrator-a", tags: ["tag-a"]),
      book("second", publisher: "publisher-b", illustrator: "illustrator-b", tags: ["tag-b"])]
    {
      try await library.store.ingest(.book(record), scope: library.scope)
    }
    let model = LibraryModel(library: library)
    model.select(.books)
    model.filters = LibraryFilters(publisherIDs: ["publisher-a", "publisher-b"],
      illustratorIDs: ["illustrator-a"], tagIDs: ["tag-a", "tag-b"])
    await model.load()
    #expect(model.items.map(\.recordID) == ["first"])
    model.filters.illustratorIDs = ["illustrator-b"]
    await model.load()
    #expect(model.items.map(\.recordID) == ["second"])
    model.filters.tagIDs = ["tag-a"]
    await model.load()
    #expect(model.items.isEmpty)
  }

  @Test func craftSwitchAndShelfHandoffResetFilters() throws {
    let model = LibraryModel(library: try localFeatureLibrary())
    model.filters.companyID = "company-a"
    let identity = model.listingIdentity
    model.select(.books)
    #expect(model.filters.isEmpty)
    #expect(model.listingIdentity != identity)
    model.filters.publisherIDs = ["publisher-a"]
    model.select(.books)
    #expect(!model.filters.isEmpty)
    model.apply(LibraryRequest(section: .books, status: "completed"))
    #expect(model.filters.isEmpty)
    #expect(model.statusFilter == "completed")
  }

  @Test func optionsUseOwnedIDsAndKeepEqualNamesDistinct() {
    let items: [LibraryItem] = [
      .diamond(project("one", company: "company-a", tags: ["tag-a"])),
      .diamond(project("two", company: "company-b", tags: ["tag-b"])),
      .diamond(project("foreign", company: "private-company", tags: ["private-tag"], user: "other-user"))]
    let options = LibraryFilterOptions(items: items, section: .diamonds, userID: "feature-user")
    #expect(options.companies.map(\.id) == ["company-a", "company-b"])
    #expect(options.tags.map(\.id) == ["tag-a", "tag-b"])
    #expect(!LibraryFilters(companyID: "company-a").matches(items[1]))
  }

  @Test func accountModelsDoNotCarrySelectionsOrOptions() async throws {
    let library = try localFeatureLibrary()
    try await library.store.ingest(.diamond(project("one", company: "company-a")), scope: library.scope)
    let first = LibraryModel(library: library)
    first.filters.companyID = "company-a"
    await first.load()
    let second = LibraryModel(library: try localFeatureLibrary(userID: "other-user"))
    await second.load()
    #expect(second.filters.isEmpty)
    #expect(second.filterOptions.companies.isEmpty)
    #expect(second.items.isEmpty)
    #expect(first.filterOptions.companies.map(\.id) == ["company-a"])
  }

  @Test func staleSelectionsRemainClearableAfterRemoval() async throws {
    let library = try localFeatureLibrary()
    let record = project("one", company: "company-a")
    try await library.store.ingest(.diamond(record), scope: library.scope)
    let model = LibraryModel(library: library)
    model.filters.companyID = "company-a"
    await model.load()
    try await library.store.removeConfirmed(scope: library.scope, key: LibraryItem.diamond(record).localRecordKey)
    await model.load()
    #expect(model.filterOptions.companies.isEmpty)
    #expect(model.filters.companyID == "company-a")
    #expect(model.items.isEmpty)
    model.resetFilters()
    #expect(model.filters.isEmpty)
  }

  private func project(_ id: String, company: String, tags: [String] = [],
    user: String = "feature-user") -> DiamondProjectRecord
  {
    DiamondProjectRecord(id: id, title: id, user: user, company: company,
      artist: "artist-a", status: "wishlist", kitCategory: "full", drillShape: "round",
      generalNotes: nil, width: nil, height: nil, image: nil, dateStarted: nil,
      dateCompleted: "2025-12-31 23:59:59.000Z", created: "2026-01-01", updated: "2026-01-01",
      expand: DiamondProjectExpand(company: NamedRelationRecord(id: company, name: "Same company"),
        artist: NamedRelationRecord(id: "artist-a", name: "Same artist"),
        projectTags: tags.map { ProjectTagRecord(id: "link-\($0)",
          expand: .init(tag: TagRecord(id: $0, name: "Same tag"))) }))
  }

  private func book(_ id: String, publisher: String, illustrator: String,
    tags: [String]) -> ColoringBookRecord
  {
    ColoringBookRecord(id: id, user: "feature-user", title: id, series: nil,
      status: "purchased", totalPages: 40, completedPages: nil, completionPercentage: nil,
      coverImage: nil, publisher: publisher, illustrator: illustrator,
      created: "2026-01-01", updated: "2026-01-01",
      expand: ColoringBookExpand(publisher: NamedRelationRecord(id: publisher, name: "Same publisher"),
        illustrator: NamedRelationRecord(id: illustrator, name: "Same illustrator"),
        bookTags: tags.map { ColoringBookTagRecord(id: "link-\($0)",
          expand: .init(tag: TagRecord(id: $0, name: "Same tag"))) }))
  }
}
