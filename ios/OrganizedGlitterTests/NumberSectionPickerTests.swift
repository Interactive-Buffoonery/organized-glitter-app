import Testing

@testable import OrganizedGlitter

@Suite("Number section picker")
struct NumberSectionPickerTests {
  @Test("accepts comma and whitespace separators and deduplicates numbers")
  func parsesCandidates() {
    #expect(NumberSectionPicker.candidates(from: " 2, 02, 8\n19\t8 ") == [2, 8, 19])
  }

  @Test("rejects invalid choices", arguments: [
    "", "   ", "1, nope, 3", "0, 2", "-1, 5", "2.5, 3",
    "9007199254740992", "999999999999999999999999", "1,", ",1", "１２", "+2",
  ])
  func rejectsInvalidChoices(input: String) {
    #expect(NumberSectionPicker.candidates(from: input) == nil)
  }

  @Test("accepts the web safe integer boundary")
  func acceptsBoundary() {
    #expect(NumberSectionPicker.candidates(from: "9007199254740991") == [9_007_199_254_740_991])
  }

  @Test("picks only from entered choices on repeated rolls")
  func picksCandidate() {
    let picker = NumberSectionPicker()
    picker.numbers = "2, 8, 19"
    var generator = FixedGenerator()
    for _ in 0..<20 {
      picker.pick(using: &generator)
      #expect([2, 8, 19].contains(picker.selectedNumber ?? 0))
      #expect(picker.errorMessage == nil)
    }
  }

  @Test("a single distinct choice can be picked again")
  func repeatsSingleChoice() {
    let picker = NumberSectionPicker()
    picker.numbers = "8, 8"
    picker.pick()
    picker.pick()
    #expect(picker.selectedNumber == 8)
  }

  @Test("editing clears a previous result and recovers from invalid input")
  func clearsStaleState() {
    let picker = NumberSectionPicker()
    picker.numbers = "8"
    picker.pick()
    #expect(picker.selectedNumber == 8)
    picker.numbers = "invalid"
    #expect(picker.selectedNumber == nil)
    picker.pick()
    #expect(picker.errorMessage != nil)
    picker.numbers = "12"
    #expect(picker.errorMessage == nil)
    picker.pick()
    #expect(picker.selectedNumber == 12)
  }

  @Test("committing unchanged input preserves the pick")
  func preservesResultOnUnchangedInput() {
    let picker = NumberSectionPicker()
    picker.numbers = "8, 8"
    picker.pick()
    picker.numbers = "8, 8"
    #expect(picker.selectedNumber == 8)
  }
}

private struct FixedGenerator: RandomNumberGenerator {
  mutating func next() -> UInt64 { UInt64.max / 2 }
}
