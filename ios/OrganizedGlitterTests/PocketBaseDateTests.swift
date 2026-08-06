import Foundation
import Testing

@testable import OrganizedGlitter

@Suite("PocketBaseDate")
struct PocketBaseDateTests {
  @Test("parses PocketBase space-separated timestamps with fractional seconds")
  func parsesSpaceSeparatedFractionalTimestamp() throws {
    let date = try #require(PocketBaseDate.date(from: "2024-01-15 10:30:00.000Z"))
    let components = Calendar(identifier: .gregorian)
      .dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)

    #expect(components.year == 2024)
    #expect(components.month == 1)
    #expect(components.day == 15)
    #expect(components.hour == 10)
    #expect(components.minute == 30)
    #expect(components.second == 0)
  }

  @Test("parses ISO timestamps without fractional seconds")
  func parsesTimestampWithoutFractionalSeconds() throws {
    let date = try #require(PocketBaseDate.date(from: "2024-01-15T10:30:00Z"))
    let components = Calendar(identifier: .gregorian)
      .dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)

    #expect(components.hour == 10)
    #expect(components.minute == 30)
  }

  @Test("round-trips through UTC ISO8601 strings")
  func roundTripsUTCString() throws {
    let original = try #require(PocketBaseDate.date(from: "2026-07-15 12:00:00.000Z"))
    let serialized = PocketBaseDate.string(from: original)
    let roundTripped = try #require(PocketBaseDate.date(from: serialized))

    #expect(serialized.hasSuffix("Z"))
    #expect(roundTripped == original)
  }

  @Test("returns nil for invalid values")
  func returnsNilForInvalidValues() {
    #expect(PocketBaseDate.date(from: "") == nil)
    #expect(PocketBaseDate.date(from: "not-a-date") == nil)
  }
}
