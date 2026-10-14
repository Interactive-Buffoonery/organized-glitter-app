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

  var eligibleStatuses: [String] {
    switch self {
    case .diamond: [DiamondStatus.progress, .kitted, .onhold].map(\.rawValue)
    case .book: [BookStatus.purchased, .inStash, .inProgress].map(\.rawValue)
    case .page: [PageStatus.notStarted, .paletteChosen, .inProgress, .onHold].map(\.rawValue)
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
  let eligibility: RandomizerEligibility
  let candidates: [RandomizerCandidate]
  let winner: RandomizerCandidate
}

@MainActor
extension LibrarySession {
  func randomizerCandidates(
    mode: RandomizerMode, statuses: Set<String>? = nil,
    selectedIDs: Set<LocalRecordKey>? = nil, verticals: VerticalPreferences
  ) -> [RandomizerCandidate] {
    guard isActive, mode.isEnabled(for: verticals) else { return [] }
    let statuses = (statuses ?? mode.defaultStatuses).intersection(mode.eligibleStatuses)
    return randomizerAccessibleItems(mode: mode).filter {
      statuses.contains($0.item.status) && (selectedIDs?.contains($0.id) ?? true)
    }
  }

  func randomizerTarget(
    id: LocalRecordKey, mode: RandomizerMode, verticals: VerticalPreferences
  ) -> LibraryItem? {
    guard isActive, mode.isEnabled(for: verticals) else { return nil }
    return ownedRandomizerItem(id: id, mode: mode)
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
    }.sorted { lhs, rhs in
      if case .book(let left) = lhs.item, case .book(let right) = rhs.item {
        let leftActivity = left.lastActivityAt?.nonEmpty ?? ""
        let rightActivity = right.lastActivityAt?.nonEmpty ?? ""
        if leftActivity != rightActivity { return leftActivity > rightActivity }
      }
      if lhs.item.updated != rhs.item.updated { return lhs.item.updated > rhs.item.updated }
      return lhs.item.id < rhs.item.id
    }
  }
}

@MainActor
@Observable
final class LibraryRandomizer {
  let library: LibrarySession
  private(set) var selection: RandomizerSelection?
  private(set) var isSelecting = false
  private(set) var wheelSpin: RandomizerWheelSpin?
  private(set) var wheelRotation: Double = 0

  init(library: LibrarySession) {
    self.library = library
  }

  @discardableResult
  func beginSelection(
    mode: RandomizerMode, statuses: Set<String>? = nil,
    selectedIDs: Set<LocalRecordKey>? = nil, verticals: VerticalPreferences,
    eligibility: [RandomizerMode: Set<String>]? = nil
  ) -> UUID? {
    var generator = SystemRandomNumberGenerator()
    return beginSelection(mode: mode, statuses: statuses, selectedIDs: selectedIDs,
      verticals: verticals, eligibility: eligibility, using: &generator)
  }

  @discardableResult
  func beginSelection(
    mode: RandomizerMode, statuses: Set<String>? = nil,
    selectedIDs: Set<LocalRecordKey>? = nil, verticals: VerticalPreferences,
    eligibility: [RandomizerMode: Set<String>]? = nil, using generator: inout some RandomNumberGenerator
  ) -> UUID? {
    guard library.isActive, !isSelecting, !Task.isCancelled else { return nil }
    let statuses = (statuses ?? mode.defaultStatuses).intersection(mode.eligibleStatuses)
    let candidates = library.randomizerCandidates(mode: mode, statuses: statuses,
      selectedIDs: selectedIDs, verticals: verticals)
    guard let winner = candidates.randomElement(using: &generator),
      let winnerIndex = candidates.firstIndex(where: { $0.id == winner.id }),
      let endRotation = RandomizerWheelGeometry.targetRotation(from: wheelRotation,
        winnerIndex: winnerIndex, count: candidates.count) else {
      reset()
      return nil
    }
    let selection = RandomizerSelection(id: UUID(), scope: library.scope, mode: mode,
      statuses: statuses, eligibility: RandomizerEligibility(mode: mode, statuses: statuses, configured: eligibility),
      candidates: candidates, winner: winner)
    self.selection = selection
    wheelSpin = RandomizerWheelSpin(selectionID: selection.id, startRotation: wheelRotation,
      endRotation: endRotation, winnerIndex: winnerIndex, count: candidates.count)
    wheelRotation = endRotation
    isSelecting = true
    return selection.id
  }

  @discardableResult
  func finishSelection(id: UUID) -> RandomizerSelection? {
    guard isSelecting, let selection, selection.id == id,
      library.isActive, !Task.isCancelled else { return nil }
    isSelecting = false
    return selection
  }

  func reset() {
    selection = nil
    isSelecting = false
    wheelSpin = nil
    wheelRotation = 0
  }

  func currentWinner(verticals: VerticalPreferences) -> LibraryItem? {
    guard !isSelecting, library.isActive, let selection, selection.scope == library.scope else { return nil }
    return library.randomizerTarget(id: selection.winner.id,
      mode: selection.mode, verticals: verticals)
  }
}
