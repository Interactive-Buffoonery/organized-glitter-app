import Foundation
import Testing

@testable import OrganizedGlitter

struct DetailDateOnlyTests {
  @Test func midnightDSTDayPreservesNewAndEditedNoteDate() throws {
    let zone = try #require(TimeZone(identifier: "America/Santiago"))
    let selectedDay = "2026-09-06"
    let pickerDate = try #require(DetailDateOnly.date(selectedDay, timeZone: zone))
    #expect(DetailDateOnly.string(from: pickerDate, timeZone: zone) == selectedDay)
    let savedDate = try #require(DetailDateOnly.date(
      DetailDateOnly.string(from: pickerDate, timeZone: zone), timeZone: zone))
    #expect(DetailDateOnly.string(from: savedDate, timeZone: zone) == selectedDay)
    #expect(DetailDateOnly.date("2026-02-30", timeZone: zone) == nil)
  }

  @Test func pickedDaySurvivesDeviceTimezoneChangeWhileEditing() throws {
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let picked = try #require(DetailDateOnly.date("2026-10-03", timeZone: tokyo))
    #expect(DetailDateOnly.string(from: picked, timeZone: losAngeles) == "2026-10-02")
    let savedDay = DetailDateOnly.string(from: picked, timeZone: tokyo)
    let redisplayed = try #require(DetailDateOnly.date(savedDay, timeZone: losAngeles))
    #expect(DetailDateOnly.string(from: redisplayed, timeZone: losAngeles) == "2026-10-03")
  }

  @Test func newNoteUsesAccountDayAndPickerComponentsRoundTrip() throws {
    let now = try #require(ISO8601DateFormatter().date(from: "2026-10-03T02:30:00Z"))
    let accountZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let accountDay = DetailDateOnly.string(from: now, timeZone: accountZone)
    #expect(accountDay == "2026-10-02")
    for identifier in ["Asia/Tokyo", "Pacific/Honolulu", "Europe/London"] {
      let pickerZone = try #require(TimeZone(identifier: identifier))
      let pickerDate = try #require(DetailDateOnly.date(accountDay, timeZone: pickerZone))
      #expect(DetailDateOnly.string(from: pickerDate, timeZone: pickerZone) == accountDay)
      let picked = try #require(DetailDateOnly.date("2026-09-18", timeZone: pickerZone))
      let pickedDay = DetailDateOnly.string(from: picked, timeZone: pickerZone)
      let saved = try #require(DetailDateOnly.date(pickedDay))
      #expect(DetailDateOnly.string(from: saved) == "2026-09-18")
    }
  }

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

  @Test(arguments: ["2026-09-18 11:00:00.000Z", "2026-09-18 23:30:00.000Z"])
  func pocketBaseDatetimeKeepsItsLocalCalendarDay(_ value: String) throws {
    for identifier in ["America/Los_Angeles", "Asia/Tokyo"] {
      let timeZone = try #require(TimeZone(identifier: identifier))
      let date = try #require(DetailDateOnly.date(value, timeZone: timeZone))
      #expect(DetailDateOnly.string(from: date, timeZone: timeZone) == "2026-09-18")
      #expect(
        DetailDateOnly.formatted(
          value, locale: Locale(identifier: "en_US"), timeZone: timeZone
        ) == "Sep 18, 2026")
    }
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
