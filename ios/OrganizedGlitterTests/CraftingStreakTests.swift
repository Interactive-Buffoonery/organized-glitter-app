import Foundation
import SwiftUI
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
      id: "diamond", project: "project", content: "", date: "2026-10-02",
      image: nil, created: "", updated: "", expand: nil)
    let coloring = ColoringProgressNoteRecord(
      id: "coloring", user: "user", page: "page", content: "", date: "2026-10-03",
      image: nil, created: "", updated: "", expand: nil)
    let entries = NotesFeed.entries(
      items: [
        .diamond(featureProject("project", title: "Garden")),
        .page(featurePage("page", book: "book", number: 1)),
      ], diamondNotes: [diamond], coloringNotes: [coloring])
    #expect(CraftingStreak.count(
      noteDates: entries.map { $0.note.date }, now: now, timeZone: .gmt) == 2)
  }

  @MainActor @Test func preferenceDefaultsOffAndPersistsPerAccount() throws {
    let suite = "CraftingStreakTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var first = AppStorage(
      wrappedValue: false, CraftingStreak.preferenceKey(userID: "first"), store: defaults)
    let second = AppStorage(
      wrappedValue: false, CraftingStreak.preferenceKey(userID: "second"), store: defaults)
    #expect(!first.wrappedValue)
    #expect(!second.wrappedValue)
    first.wrappedValue = true
    let restored = AppStorage(
      wrappedValue: false, CraftingStreak.preferenceKey(userID: "first"), store: defaults)
    #expect(restored.wrappedValue)
    #expect(!second.wrappedValue)
  }
}
