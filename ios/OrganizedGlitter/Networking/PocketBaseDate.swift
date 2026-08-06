import Foundation

/// PocketBase serializes timestamps as `2024-01-15 10:30:00.000Z` — a space
/// separator instead of `T`, and fractional seconds that `ISO8601DateFormatter`
/// rejects unless `.withFractionalSeconds` is set. Parsing without both
/// accommodations returns nil, which surfaces as a blank date in the UI and, on
/// an editor that falls back to `Date()`, silently rewrites the stored value.
enum PocketBaseDate {
  // ponytail: formatters are built per call because ISO8601DateFormatter is not
  // Sendable. Cache behind a lock only if profiling shows this on a hot path.
  private static func formatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions =
      fractionalSeconds
      ? [.withInternetDateTime, .withFractionalSeconds]
      : [.withInternetDateTime]
    return formatter
  }

  static func date(from value: String) -> Date? {
    let normalized = value.replacingOccurrences(of: " ", with: "T")
    return formatter(fractionalSeconds: true).date(from: normalized)
      ?? formatter(fractionalSeconds: false).date(from: normalized)
  }

  static func string(from date: Date) -> String {
    formatter(fractionalSeconds: true).string(from: date)
  }
}
