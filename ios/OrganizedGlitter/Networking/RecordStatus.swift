import Foundation

/// Status values per collection, matching the select options on backend `dev`.
/// Records keep the raw `String` so a value added by a newer backend still
/// decodes; use `label(for:)` and `systemImage(for:)` to present it.
protocol RecordStatus: RawRepresentable<String>, CaseIterable, Sendable
where AllCases == [Self] {
  var label: String { get }
  var systemImage: String { get }
}

extension RecordStatus {
  static func label(for rawValue: String) -> String {
    Self(rawValue: rawValue)?.label
      ?? rawValue.replacingOccurrences(of: "_", with: " ").capitalized
  }

  static func systemImage(for rawValue: String) -> String {
    Self(rawValue: rawValue)?.systemImage ?? "circle"
  }
}

enum DiamondStatus: String, RecordStatus {
  case wishlist, purchased, stash, kitted, progress, onhold, completed, archived, destashed

  var label: String {
    switch self {
    case .wishlist: "Wishlist"
    case .purchased: "Purchased"
    case .stash: "In stash"
    case .kitted: "Kitted up"
    case .progress: "In progress"
    case .onhold: "On hold"
    case .completed: "Completed"
    case .archived: "Archived"
    case .destashed: "Destashed"
    }
  }

  var systemImage: String {
    switch self {
    case .wishlist: "heart"
    case .purchased: "bag"
    case .stash: "tray.full"
    case .kitted: "shippingbox"
    case .progress: "play.circle"
    case .onhold: "pause.circle"
    case .completed: "checkmark.circle"
    case .archived: "archivebox"
    case .destashed: "arrow.up.bin"
    }
  }
}

enum BookStatus: String, RecordStatus {
  case wishlist, purchased
  case inStash = "in_stash"
  case inProgress = "in_progress"
  case completed, archived, destashed

  var label: String {
    switch self {
    case .wishlist: "Wishlist"
    case .purchased: "Purchased"
    case .inStash: "In stash"
    case .inProgress: "In progress"
    case .completed: "Completed"
    case .archived: "Archived"
    case .destashed: "Destashed"
    }
  }

  var systemImage: String {
    switch self {
    case .wishlist: "heart"
    case .purchased: "bag"
    case .inStash: "tray.full"
    case .inProgress: "play.circle"
    case .completed: "checkmark.circle"
    case .archived: "archivebox"
    case .destashed: "arrow.up.bin"
    }
  }
}

enum PageStatus: String, RecordStatus {
  case notStarted = "not_started"
  case paletteChosen = "palette_chosen"
  case inProgress = "in_progress"
  case onHold = "on_hold"
  case completed

  var label: String {
    switch self {
    case .notStarted: "Not started"
    case .paletteChosen: "Palette chosen"
    case .inProgress: "In progress"
    case .onHold: "On hold"
    case .completed: "Completed"
    }
  }

  var systemImage: String {
    switch self {
    case .notStarted: "circle.dashed"
    case .paletteChosen: "paintpalette"
    case .inProgress: "play.circle"
    case .onHold: "pause.circle"
    case .completed: "checkmark.circle"
    }
  }
}
