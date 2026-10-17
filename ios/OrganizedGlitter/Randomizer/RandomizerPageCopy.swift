import Foundation

enum RandomizerPageCopy {
  static let craft = "Craft"
  static let connection = "Connect to the internet to download your library."
  static let historyTitle = "Spin history"
  static let latest = "Latest"
  static let options = "options"
  static let noSpins = "No spins yet"
  static let loading = "Loading…"
  static let historyLoadFailed = "Couldn’t load spin history."
  static let retry = "Retry"
  static let refreshHistory = "Refresh history"
  static let moreHistory = "Show more"
  static let spinNotSent = "You’re offline. This spin wasn’t saved."
  static let spinRejected = "Couldn’t save this spin to history."
  static let spinUnknown = "Couldn’t confirm whether this spin was saved."
  static let title = "Randomizer"
  static let searchNotice = "Searching won’t change your selections."
  static let noSearchMatches = "No items match your search."
  static func searchTitle(_ mode: RandomizerMode) -> String { "Search \(selectorTitle(mode).lowercased())" }
  static let key = "Wheel key"
  static let keyTitle = "Wheel key"
  static let selectAll = "Select all"
  static let selectNone = "Deselect all"
  static let resetFilters = "Reset filters"
  static let unavailable = "This item is no longer available."
  static let clearResult = "Clear result"

  static func modeTitle(_ mode: RandomizerMode) -> String {
    switch mode {
    case .diamond: "Diamond paintings"
    case .book: "Coloring books"
    case .page: "Coloring pages"
    }
  }

  static func action(_ mode: RandomizerMode) -> String {
    switch mode {
    case .diamond: "Spin"
    case .book: "Pick a book"
    case .page: "Pick a page"
    }
  }

  static func statusTitle(_ mode: RandomizerMode) -> String {
    switch mode {
    case .diamond: "Project status"
    case .book: "Book status"
    case .page: "Page status"
    }
  }

  static func selectorTitle(_ mode: RandomizerMode) -> String {
    switch mode {
    case .diamond: "Projects"
    case .book: "Books"
    case .page: "Pages"
    }
  }

  static func selectedTitle(_ mode: RandomizerMode) -> String {
    switch mode {
    case .diamond: "Selected diamond painting"
    case .book: "Selected coloring book"
    case .page: "Selected coloring page"
    }
  }

  static func viewAction(_ mode: RandomizerMode) -> String {
    switch mode {
    case .diamond: "View project"
    case .book: "View book"
    case .page: "View page"
    }
  }

  static func status(_ status: String, mode: RandomizerMode) -> String {
    return mode.section.statusLabel(status)
  }

  static func noSelection(_ mode: RandomizerMode) -> String {
    switch mode {
    case .diamond: "No projects selected."
    case .book: "No books selected."
    case .page: "No pages selected."
    }
  }

  static func empty(_ mode: RandomizerMode) -> String {
    switch mode {
    case .diamond: "No diamond paintings match these filters."
    case .book: "No coloring books match these filters."
    case .page: "No coloring pages match these filters."
    }
  }

  static func actionAccessibility(_ mode: RandomizerMode, count: Int) -> String {
    "\(action(mode)), \(count) selected"
  }

  static func announcement(_ candidate: RandomizerCandidate) -> String {
    "Spin complete! Selected: \(candidate.title)"
  }
}
