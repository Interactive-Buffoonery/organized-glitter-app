import Foundation
import Testing

@testable import OrganizedGlitter

@Suite("Optional crafting streak")
struct CraftingStreakTests {
  private let now = DetailDateOnly.date("2026-10-03", timeZone: .gmt)!

  @Test(arguments: [
    ([String](), 0),
    (["2026-10-03"], 1),
    (["2026-10-02"], 1),
    (["2026-10-01"], 0),
    (["2026-10-03", "2026-10-02", "2026-10-01"], 3),
    (["2026-10-02", "2026-10-01"], 2),
    (["2026-10-03", "2026-10-01", "2026-09-30"], 1),
    (["2026-10-02", "2026-09-30"], 1),
    (["2026-10-03", "2026-10-03", "2026-10-02"], 2),
    (["2026-10-04", "invalid", "2026-02-30"], 0),
  ])
  func countsConsecutiveDays(dates: [String], expected: Int) {
    #expect(CraftingStreak.count(noteDates: dates, now: now, timeZone: .gmt) == expected)
  }

  @Test func usesLocalCalendarDaysAcrossTimeZones() throws {
    let instant = try #require(ISO8601DateFormatter().date(from: "2026-10-03T02:30:00Z"))
    let west = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let east = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let dates = ["2026-10-03", "2026-10-02", "2026-10-01"]
    #expect(CraftingStreak.count(noteDates: dates, now: instant, timeZone: west) == 2)
    #expect(CraftingStreak.count(noteDates: dates, now: instant, timeZone: east) == 3)
  }

  @Test func crossesDaylightSavingAndYearBoundaries() throws {
    let zone = try #require(TimeZone(identifier: "America/New_York"))
    let spring = try #require(DetailDateOnly.date("2026-03-09", timeZone: zone))
    #expect(CraftingStreak.count(
      noteDates: ["2026-03-09", "2026-03-08", "2026-03-07"],
      now: spring, timeZone: zone) == 3)
    let fall = try #require(DetailDateOnly.date("2026-11-02", timeZone: zone))
    #expect(CraftingStreak.count(
      noteDates: ["2026-11-02", "2026-11-01", "2026-10-31"],
      now: fall, timeZone: zone) == 3)
    let newYear = try #require(DetailDateOnly.date("2027-01-01", timeZone: zone))
    #expect(CraftingStreak.count(
      noteDates: ["2027-01-01", "2026-12-31"], now: newYear, timeZone: zone) == 2)
  }

  @Test func combinesBothCraftsFromTheNotesFeed() {
    let diamond = DiamondProgressNoteRecord(
      id: "diamond", project: "project", content: "", date: "2026-10-02 23:30:00.000Z",
      image: nil, created: "", updated: "", expand: nil)
    let coloring = ColoringProgressNoteRecord(
      id: "coloring", user: "user", page: "page", content: "", date: "2026-10-03 00:00:00.000Z",
      image: nil, created: "", updated: "", expand: nil)
    let entries = NotesFeed.entries(
      items: [
        .diamond(featureProject("project", title: "Garden")),
        .page(featurePage("page", book: "book", number: 1)),
      ], diamondNotes: [diamond], coloringNotes: [coloring])
    #expect(CraftingStreak.count(
      noteDates: CraftingStreak.dateLabels(in: entries), now: now, timeZone: .gmt) == 2)
  }

  @Test(arguments: [false, true])
  func migratesLegacyModeOnlyOnce(enabled: Bool) throws {
    let suite = "CraftingStreakTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(enabled, forKey: CraftingStreak.preferenceKey(userID: "first"))
    #expect(CraftingStreak.migrateMode(userID: "first", defaults: defaults) == (enabled ? "home" : "off"))
    #expect(defaults.bool(forKey: CraftingStreak.preferenceKey(userID: "first")) == enabled)
    defaults.set("notes", forKey: CraftingStreak.modeKey(userID: "first"))
    #expect(CraftingStreak.migrateMode(userID: "first", defaults: defaults) == "notes")
    #expect(CraftingStreak.migrateMode(userID: "second", defaults: defaults) == "off")
  }

  @Test(arguments: ["off", "home", "notes", "invalid", ""])
  func explicitModeAlwaysWins(raw: String) throws {
    let suite = "CraftingStreakTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: CraftingStreak.preferenceKey(userID: "first"))
    defaults.set(raw, forKey: CraftingStreak.modeKey(userID: "first"))
    let restored = CraftingStreak.migrateMode(userID: "first", defaults: defaults)
    #expect(restored == raw)
    #expect((CraftingStreakMode(rawValue: restored) ?? .off) == (CraftingStreakMode(rawValue: raw) ?? .off))
  }

  @Test func invalidNonStringModeDoesNotRemigrate() throws {
    let suite = "CraftingStreakTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: CraftingStreak.preferenceKey(userID: "first"))
    defaults.set(["invalid"], forKey: CraftingStreak.modeKey(userID: "first"))
    #expect(CraftingStreak.migrateMode(userID: "first", defaults: defaults) == "off")
  }

  @Test func requiresCompleteActiveSnapshot() {
    #expect(CraftingStreak.snapshotCount(hasSnapshot: false, isActive: true, noteDates: []) == nil)
    #expect(CraftingStreak.snapshotCount(hasSnapshot: true, isActive: false, noteDates: ["2026-10-03"]) == nil)
    #expect(CraftingStreak.snapshotCount(hasSnapshot: true, isActive: true, noteDates: [], now: now) == 0)
    #expect(CraftingStreak.snapshotCount(
      hasSnapshot: true, isActive: true, noteDates: ["2026-10-03"], now: now, timeZone: .gmt) == 1)
  }

  @MainActor @Test func downloadedNotesStayAccountScopedAndRejectInvalidSnapshots() async throws {
    let first = try localFeatureLibrary()
    let second = LibrarySession(client: first.client, userID: "second", store: first.store)
    let note = DiamondProgressNoteRecord(
      id: "note", project: "project", content: "", date: "2026-10-03 00:00:00.000Z",
      image: nil, created: "", updated: "", expand: nil)
    func snapshot(version: Int) -> LocalFullSnapshot {
      LocalFullSnapshot(version: version,
        projects: [featureProject("project", title: "Synthetic")],
        coloringBooks: [], coloringPages: [], progressNotes: [note], coloringPageProgressNotes: [])
    }
    func count(_ session: LibrarySession) -> Int? {
      CraftingStreak.snapshotCount(
        hasSnapshot: session.hasSnapshot, isActive: session.isActive,
        noteDates: CraftingStreak.dateLabels(in: NotesFeed.entries(
          items: session.items, diamondNotes: session.progressNotes,
          coloringNotes: session.coloringPageProgressNotes)),
        now: now, timeZone: .gmt)
    }
    do {
      try await first.store.ingestSnapshot(snapshot(version: 2), scope: first.scope)
      Issue.record("Expected invalid snapshot rejection")
    } catch LocalLibraryError.invalidValue {}
    try await first.loadLocal()
    #expect(count(first) == nil)
    try await first.store.ingestSnapshot(snapshot(version: 1), scope: first.scope)
    try await first.loadLocal()
    try await second.loadLocal()
    #expect(count(first) == 1)
    #expect(count(second) == nil)
    try await first.close(removingData: false)
    #expect(count(first) == nil)
  }

  @Test func sharedSyntheticCases() throws {
    let url = try #require(Bundle(for: StreakFixtureBundle.self).url(
      forResource: "crafting-streak-cases", withExtension: "json"))
    let cases = try JSONDecoder().decode([StreakCase].self, from: Data(contentsOf: url))
    for test in cases {
      let now = try #require(ISO8601DateFormatter().date(from: test.now))
      let zone = try #require(TimeZone(identifier: test.timeZone))
      #expect(CraftingStreak.count(noteDates: test.noteDates, now: now, timeZone: zone) == test.expected,
        "\(test.id)")
    }
  }
}

private final class StreakFixtureBundle: NSObject {}

private struct StreakCase: Decodable {
  let id: String
  let noteDates: [String]
  let now: String
  let timeZone: String
  let expected: Int
}
