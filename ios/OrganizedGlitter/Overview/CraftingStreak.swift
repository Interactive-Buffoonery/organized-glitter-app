import Foundation

enum CraftingStreak {
  static func preferenceKey(userID: String) -> String {
    "show-crafting-streak.\(userID)"
  }

  static func count(
    noteDates: [String], now: Date = .now, timeZone: TimeZone = .current
  ) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let days = Set(noteDates.compactMap { DetailDateOnly.date($0, timeZone: timeZone) })
    var day = calendar.startOfDay(for: now)
    if !days.contains(day) {
      guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
      day = yesterday
    }
    var count = 0
    while days.contains(day) {
      count += 1
      guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
      day = previous
    }
    return count
  }
}
