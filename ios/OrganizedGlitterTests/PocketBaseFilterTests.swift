import Testing

@testable import OrganizedGlitter

struct PocketBaseFilterTests {
  @Test
  func escapesUserValues() {
    let filter = PocketBaseFilter.equals(.title, "A \"quoted\" \\ title\n")

    #expect(filter == "title = \"A \\\"quoted\\\" \\\\ title\\n\"")
  }

  @Test
  func combinesOnlyPresentFilters() {
    let filter = PocketBaseFilter.all([
      PocketBaseFilter.equals(.user, "user-id"),
      "",
      PocketBaseFilter.equals(.status, "progress"),
    ])

    #expect(filter == "user = \"user-id\" && status = \"progress\"")
  }

  @Test
  func combinesAlternateContainsAsAGroup() {
    let filter = PocketBaseFilter.any([
      PocketBaseFilter.contains(.title, "atelier"),
      PocketBaseFilter.contains(.artistName, "atelier"),
      PocketBaseFilter.contains(.companyName, "atelier"),
    ])

    #expect(filter == #"(title ~ "atelier" || artist.name ~ "atelier" || company.name ~ "atelier")"#)
  }

  @Test
  func encodesNumericAndDateComparisons() {
    #expect(PocketBaseFilter.equals(.pageNumber, 42) == "page_number = 42")
    #expect(
      PocketBaseFilter.greaterThanOrEqual(.completedAt, "2026-07-01")
        == "completed_at >= \"2026-07-01\""
    )
    #expect(
      PocketBaseFilter.lessThan(.dateCompleted, "2026-08-01")
        == "date_completed < \"2026-08-01\""
    )
  }
}
