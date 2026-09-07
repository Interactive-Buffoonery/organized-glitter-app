import Foundation
import Observation

@Observable
final class NumberSectionPicker {
  var numbers = "" {
    didSet {
      guard numbers != oldValue else { return }
      selectedNumber = nil
      errorMessage = nil
    }
  }
  private(set) var selectedNumber: Int?
  private(set) var errorMessage: String?

  func pick() {
    var generator = SystemRandomNumberGenerator()
    pick(using: &generator)
  }

  func pick(using generator: inout some RandomNumberGenerator) {
    guard let candidates = Self.candidates(from: numbers) else {
      selectedNumber = nil
      errorMessage = "Enter whole numbers greater than zero, separated by commas."
      return
    }
    errorMessage = nil
    selectedNumber = candidates.randomElement(using: &generator)
  }

  static func candidates(from input: String) -> [Int]? {
    let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "[\\s,]+", with: ",", options: .regularExpression)
    let tokens = normalized.split(separator: ",", omittingEmptySubsequences: false)
    var seen = Set<Int>()
    var result: [Int] = []
    for token in tokens {
      guard !token.isEmpty,
        token.utf8.allSatisfy({ (48...57).contains($0) }),
        let number = Int(token), number > 0, number <= 9_007_199_254_740_991
      else { return nil }
      if seen.insert(number).inserted {
        result.append(number)
      }
    }
    return result.isEmpty ? nil : result
  }
}
