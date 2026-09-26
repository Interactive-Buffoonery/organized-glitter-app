import Foundation

enum DetailDateOnly {
  static func formatted(
    _ value: String,
    locale: Locale = .current,
    timeZone: TimeZone = .current
  ) -> String? {
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

    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
  }
}
