import Foundation

enum CraftingStreakMode: String, CaseIterable, Identifiable {
  case off
  case home
  case notes

  var id: Self { self }

  var title: String {
    switch self {
    case .off: "Off"
    case .home: "Show on Home"
    case .notes: "Show in Notes"
    }
  }
}

enum CraftingStreak {
  static func preferenceKey(userID: String) -> String {
    "show-crafting-streak.\(userID)"
  }

  static func modeKey(userID: String) -> String {
    "crafting-streak-mode.\(userID)"
  }

  static func migrateMode(userID: String, defaults: UserDefaults = .standard) -> String {
    let key = modeKey(userID: userID)
    if defaults.object(forKey: key) != nil {
      return defaults.string(forKey: key) ?? CraftingStreakMode.off.rawValue
    }
    let mode: CraftingStreakMode = defaults.bool(forKey: preferenceKey(userID: userID)) ? .home : .off
    defaults.set(mode.rawValue, forKey: key)
    return mode.rawValue
  }

  static func dateLabels(in entries: [NotesFeedEntry]) -> [String] {
    // PocketBase date fields include a time suffix; the chosen day is its leading label.
    entries.map { String($0.note.date.prefix(10)) }
  }

  static func snapshotCount(
    hasSnapshot: Bool, isActive: Bool, noteDates: [String],
    now: Date = .now, timeZone: TimeZone = .current
  ) -> Int? {
    guard hasSnapshot, isActive else { return nil }
    return count(noteDates: noteDates, now: now, timeZone: timeZone)
  }

  static func count(
    noteDates: [String], now: Date = .now, timeZone: TimeZone = .current
  ) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    // Dates are Gregorian labels, not instants in the account timezone.
    let days = Set(noteDates.compactMap { value -> Date? in
      guard value.utf8.count == 10,
        value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil
      else { return nil }
      return DetailDateOnly.date(value, timeZone: .gmt)
    })
    guard var day = DetailDateOnly.date(
      DetailDateOnly.string(from: now, timeZone: timeZone), timeZone: .gmt)
    else { return 0 }
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
