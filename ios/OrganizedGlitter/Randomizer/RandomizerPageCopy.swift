import Foundation

// Existing web copy at 62b1293; native adoption remains pending Sarah's review.
enum RandomizerPageCopy {
  static let craft = "Craft"
  static let wheelHeading = "What will you work on next?"
  static let title = "Randomizer"
  static let introduction = "Pick some or all of your in-progress projects and spin the wheel!"
  static let searchNotice = "Search only changes the list. All selected items stay on the wheel."
  static let noSearchMatches = "No items match your search."
  static func searchTitle(_ mode: RandomizerMode) -> String { "Search \(selectorTitle(mode).lowercased())" }
  static let key = "Key"
  static let keyTitle = "Wheel key"
  static let keyDescription = "Selected items by wheel number."
  static let selectAll = "Select all"
  static let selectNone = "Deselect all"
  static let resetFilters = "Reset filters"
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
    if mode == .book, status == BookStatus.inStash.rawValue { return "On Bookshelf (Not Started)" }
    return mode.section.statusLabel(status)
  }

  static func noSelection(_ mode: RandomizerMode) -> String {
    switch mode {
    case .diamond: "No projects are currently selected."
    case .book: "No books are currently selected."
    case .page: "No pages are currently selected."
    }
  }

  static func empty(_ mode: RandomizerMode) -> String {
    switch mode {
    case .diamond: "No diamond paintings match these filters."
    case .book: "No coloring books match these filters."
    case .page: "No coloring pages match these filters."
    }
  }

  static func oneItem(_ mode: RandomizerMode) -> String {
    switch mode {
    case .diamond: "Only one project is selected. We recommend selecting more projects before spinning the wheel."
    case .book: "Only one book is selected. We recommend selecting more books before spinning the wheel."
    case .page: "Only one page is selected. We recommend selecting more pages before spinning the wheel."
    }
  }

  static func actionAccessibility(_ mode: RandomizerMode, count: Int) -> String {
    mode == .diamond ? "Spin the wheel to randomly select from \(count) items"
      : "\(action(mode)) from \(count) items"
  }

  static func announcement(_ candidate: RandomizerCandidate) -> String {
    "Spin complete! Selected project: \(candidate.title)"
  }
}
