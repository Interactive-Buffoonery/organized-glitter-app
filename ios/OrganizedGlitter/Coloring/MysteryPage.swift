import Foundation

struct MysteryPagePresentation: Equatable {
  let isMystery: Bool
  let isRevealed: Bool
  let title: String

  init(page: ColoringPageRecord, isMystery: Bool) {
    self.isMystery = isMystery
    let answer = page.revealedSubject?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    isRevealed = answer != nil
    title = answer ?? "Page \(page.pageNumber)"
  }

  var hidesThumbnail: Bool { isMystery && !isRevealed }
}

enum MysteryRevealError: Error, Equatable {
  case emptySubject, invalidDate, futureDate
}

enum MysteryRevealWrite {
  static func reveal(subject: String, day: String, today: String) throws -> [String: String] {
    let answer = try trimmedAnswer(subject)
    guard day.count == 10, today.count == 10,
      DetailDateOnly.date(day, timeZone: .gmt) != nil,
      DetailDateOnly.date(today, timeZone: .gmt) != nil else { throw MysteryRevealError.invalidDate }
    guard day <= today else { throw MysteryRevealError.futureDate }
    return ["revealed_subject": answer, "revealed_at": day]
  }

  static func editAnswer(_ subject: String) throws -> [String: String] {
    ["revealed_subject": try trimmedAnswer(subject)]
  }

  static let hide = ["revealed_subject": "", "revealed_at": ""]

  private static func trimmedAnswer(_ subject: String) throws -> String {
    let answer = subject.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !answer.isEmpty else { throw MysteryRevealError.emptySubject }
    return answer
  }
}
