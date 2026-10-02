import Foundation
import Testing
@testable import OrganizedGlitter

struct LibraryItemMetadataTests {
  private let locale = Locale(identifier: "en_US")
  private let timeZone = TimeZone(secondsFromGMT: 0)!

  private func metadata(_ project: DiamondProjectRecord) -> LibraryItemMetadata {
    LibraryItemMetadata(item: .diamond(project), locale: locale, timeZone: timeZone)
  }

  private func project(_ status: String, purchased: String? = "2026-01-02",
    received: String? = "2026-02-03", started: String? = "2026-03-04",
    finished: String? = "2026-04-05") -> DiamondProjectRecord
  {
    DiamondProjectRecord(
      id: "example", title: "Moon Garden", user: "example", company: nil, artist: nil,
      status: status, kitCategory: "full", drillShape: "round", generalNotes: nil,
      width: 50, height: 70.5, image: nil, dateStarted: started, dateCompleted: finished,
      created: "2025-12-01 12:30:00.000Z", updated: "2026-04-05", expand: nil,
      datePurchased: purchased, dateReceived: received)
  }

  @Test(arguments: [
    ("wishlist", "Added 12/1/25"), ("purchased", "Purchased 1/2/26"),
    ("stash", "Received 2/3/26"), ("kitted", "Received 2/3/26"),
    ("progress", "Started 3/4/26"), ("onhold", "Started 3/4/26"),
    ("completed", "Finished 4/5/26"), ("archived", "Finished 4/5/26"),
    ("destashed", "Purchased 1/2/26"), ("future", "Purchased 1/2/26")
  ])
  func lifecycleMatchesWeb(status: String, expected: String) {
    #expect(metadata(project(status)).lifecycle == expected)
  }

  @Test func missingAndInvalidDatesFallBackWithTheirOwnLabels() {
    #expect(metadata(project("completed", finished: "invalid")).lifecycle == "Started 3/4/26")
    #expect(metadata(project("onhold", started: nil)).lifecycle == "Received 2/3/26")
    #expect(metadata(project("stash", received: "2026-02-30")).lifecycle == "Purchased 1/2/26")
    #expect(metadata(project("completed", purchased: nil, received: nil, started: nil, finished: nil))
      .lifecycle == "Added 12/1/25")
  }

  @Test func creditsAndSpecificationsOmitMissingParts() {
    let full = project("stash").withExpand(DiamondProjectExpand(
      company: NamedRelationRecord(id: "company", name: "Example Kits"),
      artist: NamedRelationRecord(id: "artist", name: "Example Artist")))
    #expect(metadata(full).maker == "Example Kits · Example Artist")
    #expect(metadata(full).specifications == "50×70.5 · Round")
    let artistOnly = full.withExpand(DiamondProjectExpand(company: nil,
      artist: NamedRelationRecord(id: "artist", name: "Example Artist")))
    #expect(metadata(artistOnly).maker == "Example Artist")
    #expect(metadata(featureProject("missing", title: "Missing")).specifications == "Round")
    #expect(metadata(full).accessibilityLabel(for: .diamond(full)) ==
      "Moon Garden, Example Kits · Example Artist, 50×70.5 · Round, Received 2/3/26, In stash")
  }

  @Test func bookShowsPublisherAndColoredCount() {
    let book = featureBook("book", title: "Quiet Pages").withExpand(ColoringBookExpand(
      publisher: NamedRelationRecord(id: "publisher", name: "Example Press"), illustrator: nil))
    let value = LibraryItemMetadata(item: .book(book))
    #expect(value.maker == "Example Press")
    #expect(value.detailLine == "0 of 40 pages colored")
    #expect(value.lifecycle.isEmpty)
  }

  @Test func lifecycleKeepsCalendarDayAcrossTimeZones() {
    let item = LibraryItem.diamond(project("wishlist"))
    let west = LibraryItemMetadata(item: item, locale: locale,
      timeZone: TimeZone(secondsFromGMT: -8 * 3600)!)
    let east = LibraryItemMetadata(item: item, locale: locale,
      timeZone: TimeZone(secondsFromGMT: 14 * 3600)!)
    #expect(west.lifecycle == "Added 12/1/25")
    #expect(east.lifecycle == west.lifecycle)
  }

  @Test func lifecycleUsesEachRequestedLocale() {
    let item = LibraryItem.diamond(project("stash"))
    let british = LibraryItemMetadata(item: item, locale: Locale(identifier: "en_GB"),
      timeZone: timeZone)
    #expect(british.lifecycle == "Received 03/02/26")
    #expect(metadata(project("stash")).lifecycle == "Received 2/3/26")
    #expect(LibraryItemMetadata(item: item, locale: Locale(identifier: "en_GB"),
      timeZone: timeZone) == british)
  }

  @Test func partialDimensionsDoNotInventSizeAndBooksKeepCounts() throws {
    var fields = try #require(JSONSerialization.jsonObject(with:
      JSONEncoder().encode(project("stash"))) as? [String: Any])
    fields.removeValue(forKey: "height")
    let partial = try JSONDecoder().decode(DiamondProjectRecord.self,
      from: JSONSerialization.data(withJSONObject: fields))
    #expect(metadata(partial).specifications == "Round")
    fields["height"] = 70
    fields.removeValue(forKey: "drill_shape")
    let sizeOnly = try JSONDecoder().decode(DiamondProjectRecord.self,
      from: JSONSerialization.data(withJSONObject: fields))
    #expect(metadata(sizeOnly).specifications == "50×70")

    var bookFields = try #require(JSONSerialization.jsonObject(with:
      JSONEncoder().encode(featureBook("book", title: "Quiet Pages"))) as? [String: Any])
    bookFields["completed_pages"] = 7
    let book = try JSONDecoder().decode(ColoringBookRecord.self,
      from: JSONSerialization.data(withJSONObject: bookFields))
    #expect(LibraryItemMetadata(item: .book(book)).specifications == "7 of 40 pages colored")

    bookFields["total_pages"] = 1
    bookFields["completed_pages"] = 0
    let single = try JSONDecoder().decode(ColoringBookRecord.self,
      from: JSONSerialization.data(withJSONObject: bookFields))
    #expect(LibraryItemMetadata(item: .book(single)).specifications == "0 of 1 page colored")
  }

  @Test func noMetadataHasNoSeparators() throws {
    let data = Data("""
      {"id":"empty","title":"Empty","user":"example","status":"wishlist",
      "kit_category":"full","created":"invalid","updated":"invalid","drill_shape":" "}
      """.utf8)
    let empty = try JSONDecoder().decode(DiamondProjectRecord.self, from: data)
    let value = metadata(empty)
    #expect(value.maker.isEmpty)
    #expect(value.specifications.isEmpty)
    #expect(value.detailLine.isEmpty)
    #expect(value.accessibilityLabel(for: .diamond(empty)) == "Empty, Wishlist")
  }
}
