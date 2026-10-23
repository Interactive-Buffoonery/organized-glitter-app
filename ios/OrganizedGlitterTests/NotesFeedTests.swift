import Foundation
import Testing

@testable import OrganizedGlitter

@Suite("Notes across crafts")
struct NotesFeedTests {
  private let project = featureProject("project", title: "Garden", status: "progress")
  private let book = featureBook("book", title: "Moonlit pages")
  private let page = featurePage("page", book: "book", number: 3, status: "completed")

  private func diamondNote(_ id: String, date: String, created: String) -> DiamondProgressNoteRecord {
    DiamondProgressNoteRecord(
      id: id, project: "project", content: "A few more drills", date: date,
      image: nil, created: created, updated: created, expand: nil)
  }

  private func pageNote(_ id: String, date: String, created: String) -> ColoringProgressNoteRecord {
    ColoringProgressNoteRecord(
      id: id, user: "feature-user", page: "page", content: "Finished the page", date: date,
      image: nil, created: created, updated: created, expand: nil)
  }

  @Test func combinesCraftsByNoteDateAndGroupsAtMonthBoundary() {
    let entries = NotesFeed.entries(
      items: [.diamond(project), .book(book), .page(page)],
      diamondNotes: [diamondNote("diamond", date: "2026-09-01", created: "2026-09-02")],
      coloringNotes: [pageNote("page", date: "2026-08-31", created: "2026-09-03")])

    #expect(entries.map(\.contextTitle) == ["Garden", "Moonlit pages · Page 3"])
    #expect(NotesFeed.months(entries).map(\.id) == ["2026-09", "2026-08"])
    #expect(NotesFeed.filter(
      entries, craft: .coloring, year: 2026,
      verticals: .init(diamondPainting: true, coloringBooks: true)
    ).map(\.id) == ["coloring-note:page"])
  }

  @Test func craftAvailabilityGatesNotesAndResolvesStaleSelections() {
    let entries = NotesFeed.entries(
      items: [.diamond(project), .book(book), .page(page)],
      diamondNotes: [diamondNote("diamond", date: "2026-09-01", created: "2026-09-02")],
      coloringNotes: [pageNote("page", date: "2025-08-31", created: "2025-09-03")])
    let cases: [(VerticalPreferences, [NotesCraft], NotesCraft, NotesCraft?, [String])] = [
      (.init(diamondPainting: true, coloringBooks: true),
       [.all, .diamond, .coloring], .all, .all,
       ["diamond-note:diamond", "coloring-note:page"]),
      (.init(diamondPainting: true, coloringBooks: false),
       [.diamond], .coloring, .diamond, ["diamond-note:diamond"]),
      (.init(diamondPainting: false, coloringBooks: true),
       [.coloring], .diamond, .coloring, ["coloring-note:page"]),
      (.init(diamondPainting: false, coloringBooks: false),
       [], .all, nil, [])
    ]

    for (verticals, available, selection, resolved, expectedIDs) in cases {
      #expect(NotesCraft.available(for: verticals) == available)
      #expect(selection.resolved(for: verticals) == resolved)
      #expect(NotesFeed.filter(
        entries, craft: selection, year: nil, verticals: verticals
      ).map(\.id) == expectedIDs)
    }

    let diamondOnly = VerticalPreferences(diamondPainting: true, coloringBooks: false)
    #expect(NotesFeed.years(in: NotesFeed.filter(
      entries, craft: .coloring, year: nil, verticals: diamondOnly
    )) == [2026])
    #expect(NotesFeed.filter(
      entries, craft: .coloring, year: 2025, verticals: diamondOnly
    ).isEmpty)
    #expect(NotesFeed.filter(
      entries, craft: .coloring, year: 2026, verticals: diamondOnly
    ).map(\.id) == ["diamond-note:diamond"])
  }

  @Test func keepsAllEligibleTargetsAvailableBeyondCurrentWork() {
    let targets = NotesFeed.noteTargets(
      items: [.page(page), .book(book), .diamond(project)],
      verticals: .init(diamondPainting: true, coloringBooks: true), search: "")

    #expect(targets.map(\.id) == ["diamond:project", "page:page"])
    #expect(targets.map(\.isInProgress) == [true, false])
    #expect(targets[1].title == "Moonlit pages · Page 3")
    #expect(NotesFeed.noteTargets(
      items: [.page(page), .book(book), .diamond(project)],
      verticals: .init(diamondPainting: false, coloringBooks: true), search: "Moonlit"
    ).map(\.id) == ["page:page"])
  }

  @Test func sameDayNotesUseCreationTimeAcrossCrafts() {
    let entries = NotesFeed.entries(
      items: [.diamond(project), .book(book), .page(page)],
      diamondNotes: [diamondNote("diamond", date: "2026-09-01", created: "2026-09-03 09:00:00")],
      coloringNotes: [pageNote("page", date: "2026-09-01", created: "2026-09-03 10:00:00")])

    #expect(entries.map(\.id) == ["coloring-note:page", "diamond-note:diamond"])
  }

  @Test func omitsNotesWhoseTargetIsAbsentFromTheAccountLibrary() {
    let entries = NotesFeed.entries(
      items: [.diamond(project)],
      diamondNotes: [diamondNote("visible", date: "2026-09-01", created: "2026-09-01")],
      coloringNotes: [pageNote("hidden", date: "2026-09-02", created: "2026-09-02")])

    #expect(entries.map(\.id) == ["diamond-note:visible"])
  }

  @Test func sourceFilteringUsesIDsAndCombinesWithCraftAndYear() {
    let duplicate = featureProject("other", title: "Garden", status: "progress")
    let sibling = featurePage("sibling", book: "book", number: 4)
    let otherBook = featureBook("other-book", title: "Moonlit pages")
    let otherPage = featurePage("other-page", book: "other-book", number: 3)
    let entries = NotesFeed.entries(
      items: [.diamond(project), .diamond(duplicate), .book(book), .page(page),
        .page(sibling), .book(otherBook), .page(otherPage)],
      diamondNotes: [
        diamondNote("current", date: "2026-09-01", created: "2026-09-02"),
        DiamondProgressNoteRecord(
          id: "duplicate", project: "other", content: "", date: "2026-09-03",
          image: nil, created: "2026-09-03", updated: "2026-09-03", expand: nil)],
      coloringNotes: [
        pageNote("older", date: "2025-09-01", created: "2025-09-02"),
        ColoringProgressNoteRecord(
          id: "sibling", user: "feature-user", page: "sibling", content: "", date: "2026-09-01",
          image: nil, created: "2026-09-04", updated: "2026-09-04", expand: nil),
        ColoringProgressNoteRecord(
          id: "other-page", user: "feature-user", page: "other-page", content: "", date: "2026-09-05",
          image: nil, created: "2026-09-05", updated: "2026-09-05", expand: nil)])
    let verticals = VerticalPreferences(diamondPainting: true, coloringBooks: true)

    #expect(NotesFeed.filter(
      entries, craft: .all, year: nil, verticals: verticals, source: .project("project")
    ).map(\.id) == ["diamond-note:current"])
    let bookEntries = NotesFeed.filter(
      entries, craft: .coloring, year: nil, verticals: verticals, source: .book("book"))
    #expect(bookEntries.map(\.id) == ["coloring-note:sibling", "coloring-note:older"])
    #expect(NotesFeed.filter(
      entries, craft: .all, year: 2026, verticals: verticals, source: .book("book")
    ).map(\.id) == ["coloring-note:sibling"])
    #expect(NotesFeed.filter(
      entries, craft: .diamond, year: nil, verticals: verticals, source: .book("book")
    ).isEmpty)
    #expect(NotesFeed.months(bookEntries).map(\.id) == ["2026-09", "2025-09"])
  }

  @Test func sourceOptionsRejectMissingAccountSourcesAndStaleCraftSelections() {
    let entries = NotesFeed.entries(
      items: [.diamond(project), .book(book), .page(page)],
      diamondNotes: [diamondNote("diamond", date: "2026-09-01", created: "2026-09-02")],
      coloringNotes: [pageNote("page", date: "2025-08-31", created: "2025-09-03")])
    let items: [LibraryItem] = [.diamond(project), .book(book), .page(page)]
    let sources = NotesFeed.sources(in: entries, items: items)
    #expect(sources.map(\.id) == [.project("project"), .book("book")])
    #expect(NotesFeed.resolvedSource(.book("book"), in: sources) == .book("book"))

    let coloring = NotesFeed.filter(
      entries, craft: .coloring, year: nil,
      verticals: .init(diamondPainting: true, coloringBooks: true))
    let coloringSources = NotesFeed.sources(in: coloring, items: items)
    #expect(coloringSources.map(\.id) == [.book("book")])
    #expect(NotesFeed.resolvedSource(.project("project"), in: coloringSources) == nil)
    #expect(NotesFeed.sources(in: entries, items: [.page(page)]).isEmpty)
    #expect(NotesFeed.resolvedSource(.book("book"), in: []) == nil)
    #expect(NotesFeed.sources(in: [], items: items).isEmpty)

    let otherAccount = [LibraryItem.diamond(featureProject("different", title: "Garden"))]
    let accountSources = NotesFeed.sources(in: entries, items: otherAccount)
    #expect(accountSources.isEmpty)
    #expect(NotesFeed.resolvedSource(.project("project"), in: accountSources) == nil)
  }


  @Test func projectAndBookIDsRemainDistinctWhenRecordIDsMatch() {
    let sharedBook = featureBook("project", title: "Garden")
    let sharedPage = featurePage("shared-page", book: "project", number: 1)
    let entries = NotesFeed.entries(
      items: [.diamond(project), .book(sharedBook), .page(sharedPage)],
      diamondNotes: [diamondNote("diamond", date: "2026-09-01", created: "2026-09-01")],
      coloringNotes: [ColoringProgressNoteRecord(
        id: "coloring", user: "feature-user", page: "shared-page", content: "", date: "2026-09-02",
        image: nil, created: "2026-09-02", updated: "2026-09-02", expand: nil)])
    let verticals = VerticalPreferences(diamondPainting: true, coloringBooks: true)
    #expect(NotesFeed.filter(
      entries, craft: .all, year: nil, verticals: verticals, source: .book("project")
    ).map(\.id) == ["coloring-note:coloring"])
    #expect(NotesFeed.filter(
      entries, craft: .all, year: nil, verticals: verticals, source: .project("project")
    ).map(\.id) == ["diamond-note:diamond"])
    #expect(NotesFeed.filter(
      entries, craft: .all, year: nil,
      verticals: .init(diamondPainting: true, coloringBooks: false), source: .book("project")
    ).isEmpty)
  }

}
