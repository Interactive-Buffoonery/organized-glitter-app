import Testing

@testable import OrganizedGlitter

struct RecordStatusTests {
  /// Select values on backend `dev` (`docs/pocketbase/collections.schema.json`).
  @Test
  func statusesMatchBackendSelectOptions() {
    #expect(
      Set(DiamondStatus.allCases.map(\.rawValue)) == [
        "wishlist", "purchased", "stash", "progress", "completed", "archived", "destashed",
        "onhold", "kitted",
      ])
    #expect(
      Set(BookStatus.allCases.map(\.rawValue)) == [
        "wishlist", "purchased", "in_stash", "in_progress", "completed", "archived", "destashed",
      ])
    #expect(
      Set(PageStatus.allCases.map(\.rawValue)) == [
        "not_started", "palette_chosen", "in_progress", "on_hold", "completed",
      ])
  }

  @Test
  func labelsAndSymbolsAreDistinctWithinACollection() {
    #expect(Set(DiamondStatus.allCases.map(\.systemImage)).count == DiamondStatus.allCases.count)
    #expect(Set(BookStatus.allCases.map(\.systemImage)).count == BookStatus.allCases.count)
    #expect(Set(PageStatus.allCases.map(\.systemImage)).count == PageStatus.allCases.count)
    #expect(DiamondStatus.label(for: "kitted") == "Kitted up")
    #expect(BookStatus.label(for: "in_stash") == "In stash")
    #expect(PageStatus.label(for: "palette_chosen") == "Palette chosen")
  }

  @Test
  func unknownValuesFromANewerBackendStillRender() {
    #expect(DiamondStatus.label(for: "gifted_away") == "Gifted Away")
    #expect(DiamondStatus.systemImage(for: "gifted_away") == "circle")
  }

  @Test
  func generatedCoverPaletteIsStablePerRecord() {
    // Fixed expectations: `Hasher` would change these on every launch.
    #expect(GeneratedCover.paletteIndex(for: "") == 5)  // FNV offset basis % 6
    #expect(GeneratedCover.paletteIndex(for: "abc123") == GeneratedCover.paletteIndex(for: "abc123"))
    let indexes = Set((0..<40).map { GeneratedCover.paletteIndex(for: "record-\($0)") })
    #expect(indexes.count == GeneratedCover.palettes.count)
  }
}
