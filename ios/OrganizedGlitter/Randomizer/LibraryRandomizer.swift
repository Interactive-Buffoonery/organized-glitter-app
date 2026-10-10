import Foundation
import Observation

enum RandomizerMode: String, CaseIterable, Identifiable, Sendable {
  case diamond, book, page

  var id: Self { self }

  var section: LibrarySection {
    switch self {
    case .diamond: .diamonds
    case .book: .books
    case .page: .pages
    }
  }

  var defaultStatuses: Set<String> {
    switch self {
    case .diamond: [DiamondStatus.progress.rawValue]
    case .book: [BookStatus.inProgress.rawValue]
    case .page: [PageStatus.paletteChosen.rawValue, PageStatus.inProgress.rawValue]
    }
  }

  func isEnabled(for verticals: VerticalPreferences) -> Bool {
    switch self {
    case .diamond: verticals.diamondPainting
    case .book, .page: verticals.coloringBooks
    }
  }
}

struct RandomizerCandidate: Identifiable, Equatable, Sendable {
  let item: LibraryItem
  let bookTitle: String?

  var id: LocalRecordKey { item.localRecordKey }
  var title: String { item.title }
}

struct RandomizerSelection: Identifiable, Equatable, Sendable {
  let id: UUID
  let scope: LocalAccountScope
  let mode: RandomizerMode
  let statuses: Set<String>
  let candidates: [RandomizerCandidate]
  let winner: RandomizerCandidate
}

@MainActor
extension LibrarySession {
  func randomizerCandidates(
    mode: RandomizerMode, statuses: Set<String>? = nil,
    selectedIDs: Set<LocalRecordKey>? = nil, verticals: VerticalPreferences
  ) -> [RandomizerCandidate] {
    guard mode.isEnabled(for: verticals) else { return [] }
    let statuses = statuses ?? mode.defaultStatuses
    return randomizerAccessibleItems(mode: mode).filter {
      statuses.contains($0.item.status) && (selectedIDs?.contains($0.id) ?? true)
    }
  }

  func randomizerTarget(
    id: LocalRecordKey, mode: RandomizerMode, verticals: VerticalPreferences
  ) -> LibraryItem? {
    guard mode.isEnabled(for: verticals) else { return nil }
    return randomizerAccessibleItems(mode: mode).first { $0.id == id }?.item
  }

  private func randomizerAccessibleItems(mode: RandomizerMode) -> [RandomizerCandidate] {
    RandomizerCandidate.owned(entries: entries, userID: userID, mode: mode)
  }
}

extension RandomizerCandidate {
  static func owned(
    entries: [LocalLibraryEntry], userID: String, mode: RandomizerMode
  ) -> [Self] {
    let accessibleItems = entries.filter { $0.conflict != .deletedOnServer }.map(\.item)
    var titles: [String: String] = [:]
    for item in accessibleItems {
      if case .book(let book) = item, book.user == userID {
        titles[book.id] = book.title
      }
    }
    var seen: Set<LocalRecordKey> = []
    return accessibleItems.compactMap { item in
      guard item.belongs(to: mode.section, userID: userID, bookTitles: titles),
        seen.insert(item.localRecordKey).inserted else { return nil }
      let bookTitle: String?
      if case .page(let page) = item { bookTitle = titles[page.book] }
      else { bookTitle = nil }
      return RandomizerCandidate(item: item, bookTitle: bookTitle)
    }.sorted { $0.item.id < $1.item.id }
  }
}

@MainActor
@Observable
final class LibraryRandomizer {
  let library: LibrarySession
  private(set) var selection: RandomizerSelection?
  private(set) var isSelecting = false

  init(library: LibrarySession) {
    self.library = library
  }

  @discardableResult
  func beginSelection(
    mode: RandomizerMode, statuses: Set<String>? = nil,
    selectedIDs: Set<LocalRecordKey>? = nil, verticals: VerticalPreferences
  ) -> UUID? {
    var generator = SystemRandomNumberGenerator()
    return beginSelection(mode: mode, statuses: statuses, selectedIDs: selectedIDs,
      verticals: verticals, using: &generator)
  }

  @discardableResult
  func beginSelection(
    mode: RandomizerMode, statuses: Set<String>? = nil,
    selectedIDs: Set<LocalRecordKey>? = nil, verticals: VerticalPreferences,
    using generator: inout some RandomNumberGenerator
  ) -> UUID? {
    guard !isSelecting, !Task.isCancelled else { return nil }
    let statuses = statuses ?? mode.defaultStatuses
    let candidates = library.randomizerCandidates(mode: mode, statuses: statuses,
      selectedIDs: selectedIDs, verticals: verticals)
    let previousID = selection?.mode == mode ? selection?.winner.id : nil
    let drawCandidates = candidates.count > 1
      ? candidates.filter { $0.id != previousID } : candidates
    guard let winner = drawCandidates.randomElement(using: &generator) else {
      selection = nil
      return nil
    }
    let selection = RandomizerSelection(id: UUID(), scope: library.scope, mode: mode,
      statuses: statuses, candidates: candidates, winner: winner)
    self.selection = selection
    isSelecting = true
    return selection.id
  }

  func finishSelection(id: UUID) {
    guard selection?.id == id, !Task.isCancelled else { return }
    isSelecting = false
  }

  func reset() {
    selection = nil
    isSelecting = false
  }

  func currentWinner(verticals: VerticalPreferences) -> LibraryItem? {
    guard !isSelecting, let selection, selection.scope == library.scope else { return nil }
    return library.randomizerTarget(id: selection.winner.id,
      mode: selection.mode, verticals: verticals)
  }
}
