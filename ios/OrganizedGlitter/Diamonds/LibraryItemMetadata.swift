import Foundation

struct LibraryItemMetadata: Equatable {
  let maker: String
  let specifications: String
  let lifecycle: String

  var detailLine: String {
    Self.join([specifications, lifecycle])
  }

  func accessibilityLabel(for item: LibraryItem) -> String {
    [item.title, maker, specifications, lifecycle, item.statusLabel]
      .filter { !$0.isEmpty }.joined(separator: ", ")
  }

  init(
    item: LibraryItem,
    locale: Locale = .current,
    timeZone: TimeZone = .current
  ) {
    switch item {
    case .diamond(let project):
      maker = Self.join([project.expand?.company?.name, project.expand?.artist?.name])
      let size: String?
      if let width = project.width, let height = project.height,
        width.isFinite, height.isFinite
      {
        let format = FloatingPointFormatStyle<Double>.number.locale(locale)
        size = "\(width.formatted(format))×\(height.formatted(format))"
      } else {
        size = nil
      }
      specifications = Self.join([size, project.drillShape?.capitalized])
      lifecycle = Self.lifecycle(project, locale: locale, timeZone: timeZone)
    case .book(let book):
      maker = Self.join([book.expand?.publisher?.name])
      specifications = "\(book.completedPages ?? 0) of \(book.totalPages) pages colored"
      lifecycle = ""
    case .page(let page):
      maker = Self.join([page.expand?.book?.title])
      specifications = "Page \(page.pageNumber)"
      lifecycle = ""
    }
  }

  private static func join(_ parts: [String?]) -> String {
    parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty }
      .joined(separator: " · ")
  }

  private static func lifecycle(
    _ project: DiamondProjectRecord, locale: Locale, timeZone: TimeZone
  ) -> String {
    let added = ("Added", Optional(project.created))
    let purchased = ("Purchased", project.datePurchased)
    let received = ("Received", project.dateReceived)
    let started = ("Started", project.dateStarted)
    let finished = ("Finished", project.dateCompleted)
    let candidates: [(String, String?)]
    switch DiamondStatus(rawValue: project.status) {
    case .wishlist: candidates = [added]
    case .purchased, .destashed, nil: candidates = [purchased, added]
    case .stash, .kitted: candidates = [received, purchased, added]
    case .progress, .onhold: candidates = [started, received, purchased, added]
    case .completed, .archived: candidates = [finished, started, received, purchased, added]
    }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.dateStyle = .short
    formatter.timeStyle = .none
    for (label, value) in candidates {
      if let value, let date = DetailDateOnly.date(value, timeZone: timeZone) {
        return "\(label) \(formatter.string(from: date))"
      }
    }
    return ""
  }
}

enum LibraryViewMode: String, CaseIterable, Identifiable {
  case covers, compact, list

  var id: String { rawValue }
  var title: String { rawValue.capitalized }
  var systemImage: String {
    switch self {
    case .covers: "square.grid.2x2"
    case .compact: "square.grid.3x3"
    case .list: "list.bullet"
    }
  }
}
