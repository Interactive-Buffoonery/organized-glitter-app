import Foundation

enum NotesCraft: String, CaseIterable, Identifiable, Sendable {
  case all
  case diamond
  case coloring

  var id: Self { self }

  var title: String {
    switch self {
    case .all: "All"
    case .diamond: "Diamond"
    case .coloring: "Coloring"
    }
  }

  static func available(for verticals: VerticalPreferences) -> [NotesCraft] {
    switch (verticals.diamondPainting, verticals.coloringBooks) {
    case (true, true): [.all, .diamond, .coloring]
    case (true, false): [.diamond]
    case (false, true): [.coloring]
    case (false, false): []
    }
  }

  func resolved(for verticals: VerticalPreferences) -> NotesCraft? {
    let available = Self.available(for: verticals)
    return available.contains(self) ? self : available.first
  }
}

/// One progress note with the project or page it belongs to.
struct NotesFeedEntry: Identifiable, Hashable, Sendable {
  let note: ProgressNoteItem
  let target: LibraryItem
  /// "Peony Garden", or "Garden Friends · Page 3".
  let contextTitle: String

  var id: String { note.id }

  var craft: NotesCraft {
    if case .diamond = note { return .diamond }
    return .coloring
  }

  var year: Int? { Int(note.date.prefix(4)) }
}

struct NotesFeedMonth: Identifiable, Hashable, Sendable {
  /// `yyyy-MM`.
  let id: String
  let entries: [NotesFeedEntry]

  /// "September 2026". Built from the key so a note on the 1st never drifts a month.
  func title(locale: Locale = .current) -> String {
    let parts = id.split(separator: "-").compactMap { Int($0) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    guard parts.count == 2,
      let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 1))
    else { return id }
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = .gmt
    formatter.locale = locale
    formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
    return formatter.string(from: date)
  }
}

enum NotesFeed {
  /// Every downloaded note whose project or page is still in the library, newest first.
  static func entries(
    items: [LibraryItem],
    diamondNotes: [DiamondProgressNoteRecord],
    coloringNotes: [ColoringProgressNoteRecord]
  ) -> [NotesFeedEntry] {
    var projects: [String: LibraryItem] = [:]
    var pages: [String: ColoringPageRecord] = [:]
    var bookTitles: [String: String] = [:]
    for item in items {
      switch item {
      case .diamond(let project): projects[project.id] = item
      case .page(let page): pages[page.id] = page
      case .book(let book): bookTitles[book.id] = book.title
      }
    }
    let diamond = diamondNotes.compactMap { note -> NotesFeedEntry? in
      guard let target = projects[note.project] else { return nil }
      return NotesFeedEntry(note: .diamond(note), target: target, contextTitle: target.title)
    }
    let coloring = coloringNotes.compactMap { note -> NotesFeedEntry? in
      guard let page = pages[note.page] else { return nil }
      return NotesFeedEntry(
        note: .coloring(note), target: .page(page),
        contextTitle: pageTitle(page, bookTitle: bookTitles[page.book]))
    }
    return (diamond + coloring).sorted(by: precedes)
  }

  static func pageTitle(_ page: ColoringPageRecord, bookTitle: String?) -> String {
    let book = bookTitle ?? page.expand?.book?.title
    return [book, "Page \(page.pageNumber)"].compactMap { $0 }.joined(separator: " · ")
  }

  /// Date, then creation time, then ID, matching the web feed.
  static func precedes(_ lhs: NotesFeedEntry, _ rhs: NotesFeedEntry) -> Bool {
    let left = lhs.note.date.prefix(10)
    let right = rhs.note.date.prefix(10)
    if left != right { return left > right }
    if lhs.note.created != rhs.note.created { return lhs.note.created > rhs.note.created }
    return lhs.note.recordID > rhs.note.recordID
  }

  static func filter(
    _ entries: [NotesFeedEntry], craft: NotesCraft, year: Int?, verticals: VerticalPreferences
  ) -> [NotesFeedEntry] {
    let available = NotesCraft.available(for: verticals)
    guard let selected = craft.resolved(for: verticals) else { return [] }
    return entries.filter {
      available.contains($0.craft)
        && (selected == .all || $0.craft == selected)
        && (year == nil || $0.year == year)
    }
  }

  /// Newest year first.
  static func years(in entries: [NotesFeedEntry]) -> [Int] {
    Set(entries.compactMap(\.year)).sorted(by: >)
  }

  /// Consecutive month groups; `entries` must already be sorted newest first.
  static func months(_ entries: [NotesFeedEntry]) -> [NotesFeedMonth] {
    var months: [NotesFeedMonth] = []
    var current: [NotesFeedEntry] = []
    var key: String?
    for entry in entries {
      let entryKey = String(entry.note.date.prefix(7))
      if entryKey != key, let key {
        months.append(NotesFeedMonth(id: key, entries: current))
        current = []
      }
      key = entryKey
      current.append(entry)
    }
    if let key { months.append(NotesFeedMonth(id: key, entries: current)) }
    return months
  }

  /// Projects and pages a note can attach to, with current work first.
  static func noteTargets(
    items: [LibraryItem], verticals: VerticalPreferences, search: String
  ) -> [NoteTarget] {
    let available = NotesCraft.available(for: verticals)
    var bookTitles: [String: String] = [:]
    for case .book(let book) in items { bookTitles[book.id] = book.title }
    let targets = items.compactMap { item -> NoteTarget? in
      switch item {
      case .diamond(let project) where available.contains(.diamond):
        return NoteTarget(
          item: item, title: project.title, subtitle: item.subtitle.nonEmpty ?? "Diamond painting",
          isInProgress: project.status == "progress")
      case .page(let page) where available.contains(.coloring):
        return NoteTarget(
          item: item, title: pageTitle(page, bookTitle: bookTitles[page.book]),
          subtitle: page.revealedSubject?.nonEmpty ?? PageStatus.label(for: page.status),
          isInProgress: page.status == "in_progress")
      default:
        return nil
      }
    }
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
    let matches = query.isEmpty
      ? targets
      : targets.filter {
        $0.title.localizedStandardContains(query) || $0.subtitle.localizedStandardContains(query)
      }
    return matches.sorted {
      if $0.isInProgress != $1.isInProgress { return $0.isInProgress }
      if $0.item.updated != $1.item.updated { return $0.item.updated > $1.item.updated }
      return $0.title.localizedStandardCompare($1.title) == .orderedAscending
    }
  }
}

struct NoteTarget: Identifiable, Hashable, Sendable {
  let item: LibraryItem
  let title: String
  let subtitle: String
  let isInProgress: Bool

  var id: String { item.id }
}
