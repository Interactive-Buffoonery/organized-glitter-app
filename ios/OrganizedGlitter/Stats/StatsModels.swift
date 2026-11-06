import Foundation

struct DiamondStatsSummary: Codable, Equatable, Sendable {
  struct Metrics: Codable, Equatable, Sendable {
    let totalKits: Int
    let completedThisYear: Int
    let inProgress: Int
    let inStash: Int
    let allTimeCompleted: Int
    let wishlistSize: Int
  }

  let generatedAt: String
  let year: Int
  let metrics: Metrics
  let statusBreakdown: [String: Int]
}

struct ColoringStatsSummary: Codable, Equatable, Sendable {
  struct Metrics: Codable, Equatable, Sendable {
    let totalBooks: Int
    let completedPagesThisYear: Int
    let activePages: Int
    let inStash: Int
    let allTimeCompletedPages: Int
    let wishlistSize: Int
  }

  let generatedAt: String
  let year: Int
  let metrics: Metrics
  let bookStatusBreakdown: [String: Int]
  let pageStatusBreakdown: [String: Int]
}

struct StatsCompletions: Codable, Equatable, Sendable {
  struct Month: Codable, Equatable, Sendable, Identifiable {
    let month: Int
    let label: String
    let count: Int
    let previousYearCount: Int
    let previousYearDelta: Int
    let averageCompletionDays: Double?

    var id: Int { month }
  }

  let generatedAt: String
  let year: Int
  let total: Int
  let months: [Month]
}

struct StatsSnapshot: Equatable, Sendable {
  let diamond: DiamondStatsSummary
  let coloring: ColoringStatsSummary
}

struct StatsTile: Equatable, Identifiable {
  let title: String
  let value: Int
  var id: String { title }
}

extension DiamondStatsSummary {
  var tiles: [StatsTile] {
    [
      StatsTile(title: "Finished in \(year)", value: metrics.completedThisYear),
      StatsTile(title: "All-time finished", value: metrics.allTimeCompleted),
      StatsTile(title: "In progress", value: metrics.inProgress),
      StatsTile(title: "In stash", value: metrics.inStash),
      StatsTile(title: "Wishlist", value: metrics.wishlistSize),
      StatsTile(title: "Total kits", value: metrics.totalKits),
    ]
  }
}

extension ColoringStatsSummary {
  var tiles: [StatsTile] {
    [
      StatsTile(title: "Pages finished in \(year)", value: metrics.completedPagesThisYear),
      StatsTile(title: "All-time pages finished", value: metrics.allTimeCompletedPages),
      StatsTile(title: "Active pages", value: metrics.activePages),
      StatsTile(title: "Books in stash", value: metrics.inStash),
      StatsTile(title: "Wishlist", value: metrics.wishlistSize),
      StatsTile(title: "Total books", value: metrics.totalBooks),
    ]
  }
}

enum StatsGeneratedTime {
  static func date(from value: String) -> Date? {
    let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    return (try? fractional.parse(value)) ?? (try? Date.ISO8601FormatStyle().parse(value))
  }
}
