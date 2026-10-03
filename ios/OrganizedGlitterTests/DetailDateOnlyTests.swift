import Foundation
import Testing

@testable import OrganizedGlitter

struct DetailDateOnlyTests {
  @Test
  func midnightUTCValueKeepsItsCalendarDayInNewYork() throws {
    let locale = Locale(identifier: "en_US")
    let timeZone = try #require(TimeZone(identifier: "America/New_York"))

    let formatted = DetailDateOnly.formatted(
      "2026-09-19 00:00:00.000Z",
      locale: locale,
      timeZone: timeZone
    )

    #expect(formatted == "Sep 19, 2026")
  }

  @Test
  func rejectsInvalidLeadingCalendarDate() {
    let formatted = DetailDateOnly.formatted(
      "2026-02-30 00:00:00.000Z",
      locale: Locale(identifier: "en_US"),
      timeZone: TimeZone(identifier: "America/New_York")!
    )

    #expect(formatted == nil)
  }

  @Test
  func elapsedPicksOneReadableUnit() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US")
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    let start = try #require(DetailDateOnly.date("2026-08-14", timeZone: calendar.timeZone))
    func after(_ days: Int) -> String? {
      DetailDateOnly.elapsed(
        from: start, to: start.addingTimeInterval(Double(days) * 86_400), calendar: calendar)
    }

    #expect(after(1) == "1 day")
    #expect(after(13) == "13 days")
    #expect(after(43) == "6 weeks")
    #expect(after(62) == "8 weeks")
    #expect(after(63) == "2 months")
    #expect(after(130) == "4 months")
    #expect(after(-1) == nil)
  }

  @Test
  func elapsedCountsCompletedCalendarMonthsAcrossShortMonths() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US")
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    let start = try #require(DetailDateOnly.date("2026-02-01", timeZone: calendar.timeZone))
    let beforeThreeMonths = try #require(
      DetailDateOnly.date("2026-04-30", timeZone: calendar.timeZone))
    let threeMonths = try #require(
      DetailDateOnly.date("2026-05-01", timeZone: calendar.timeZone))

    #expect(DetailDateOnly.elapsed(from: start, to: beforeThreeMonths, calendar: calendar) == "2 months")
    #expect(DetailDateOnly.elapsed(from: start, to: threeMonths, calendar: calendar) == "3 months")
  }

  @Test
  func webRichTextNotesBecomePlainText() {
    let html = "<p>Soft <strong>pink</strong> roses</p><p>Salt &amp; Pepper&nbsp;&lt;3</p><ul><li>AB drills</li></ul>"
    #expect(html.plainTextFromHTML == "Soft pink roses\nSalt & Pepper <3\n• AB drills")
    #expect("Plain & simple".plainTextFromHTML == "Plain & simple")
    #expect("1 < 2 and 3 > 1".plainTextFromHTML == "1 < 2 and 3 > 1")
    #expect("Use a < b and c > d".plainTextFromHTML == "Use a < b and c > d")
    #expect("<p>Use 1 < 2 and 3 > 1</p>".plainTextFromHTML == "Use 1 < 2 and 3 > 1")
  }
}
