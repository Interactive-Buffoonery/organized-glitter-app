import Foundation

enum DetailDateOnly {
  static func date(_ value: String, timeZone: TimeZone = .current) -> Date? {
    let prefix = String(value.prefix(10))
    guard prefix.count == 10 else { return nil }

    let parser = DateFormatter()
    parser.calendar = Calendar(identifier: .gregorian)
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.timeZone = timeZone
    parser.dateFormat = "yyyy-MM-dd"
    parser.isLenient = false
    guard let date = parser.date(from: prefix), parser.string(from: date) == prefix else {
      return nil
    }
    return date
  }

  static func formatted(
    _ value: String,
    locale: Locale = .current,
    timeZone: TimeZone = .current
  ) -> String? {
    guard let date = date(value, timeZone: timeZone) else { return nil }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
  }

  /// "Sep 3", for the spec strip.
  static func monthDay(
    _ value: String,
    locale: Locale = .current,
    timeZone: TimeZone = .current
  ) -> String? {
    guard let date = date(value, timeZone: timeZone) else { return nil }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.setLocalizedDateFormatFromTemplate("MMMd")
    return formatter.string(from: date)
  }

  /// "5 days", "6 weeks", "4 months": one unit, rounded down.
  static func elapsed(
    from start: Date,
    to end: Date,
    calendar: Calendar = .current
  ) -> String? {
    guard let days = calendar.dateComponents([.day], from: start, to: end).day, days >= 0 else {
      return nil
    }
    var components = DateComponents()
    let unit: NSCalendar.Unit
    switch days {
    case ..<14:
      components.day = days
      unit = .day
    case ..<63:
      components.weekOfMonth = days / 7
      unit = .weekOfMonth
    default:
      components.month = calendar.dateComponents([.month], from: start, to: end).month ?? 0
      unit = .month
    }
    let formatter = DateComponentsFormatter()
    formatter.calendar = calendar
    formatter.unitsStyle = .full
    formatter.allowedUnits = unit
    formatter.zeroFormattingBehavior = .dropLeading
    return formatter.string(from: components)
  }
}

extension String {
  /// general_notes is rich text from the web editor. Show it as plain text.
  var plainTextFromHTML: String {
    guard contains("<") || contains("&") else { return self }
    var text = replacingOccurrences(
      of: #"<\s*(br|/p|/li|/h[1-6]|/div)\b[^>]*>"#, with: "\n",
      options: [.regularExpression, .caseInsensitive])
    text = text.replacingOccurrences(of: #"<li\b[^>]*>"#, with: "• ", options: [.regularExpression, .caseInsensitive])
    text = text.replacingOccurrences(
      of: #"<\s*/?\s*(?:p|div|span|br|strong|b|em|i|u|ul|ol|li|h[1-6]|a|blockquote)\b(?:\s+[\w:-]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+))*\s*/?>"#,
      with: "", options: [.regularExpression, .caseInsensitive])
    for (entity, character) in [
      ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"),
      ("&apos;", "'"), ("&amp;", "&"),
    ] {
      text = text.replacingOccurrences(of: entity, with: character)
    }
    return text
      .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
