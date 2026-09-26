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
}
