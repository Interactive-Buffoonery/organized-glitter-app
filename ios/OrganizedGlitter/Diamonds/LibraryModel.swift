import Foundation
import Observation

enum LibrarySection: String, CaseIterable, Identifiable {
  case diamonds = "Diamond projects"
  case books = "Coloring books"
  case pages = "Coloring pages"

  var id: Self { self }

  static func available(for verticals: VerticalPreferences) -> [Self] {
    allCases.filter { section in
      switch section {
      case .diamonds:
        verticals.diamondPainting
      case .books, .pages:
        verticals.coloringBooks
      }
    }
  }

  var systemImage: String {
    switch self {
    case .diamonds: "sparkles.rectangle.stack"
    case .books: "books.vertical"
    case .pages: "pencil.and.scribble"
    }
  }

  var pickerTitle: String {
    switch self {
    case .diamonds: "Diamond art"
    case .books: "Books"
    case .pages: "Pages"
    }
  }

  var statusOptions: [String] {
    switch self {
    case .diamonds: DiamondStatus.allCases.map(\.rawValue)
    case .books: BookStatus.allCases.map(\.rawValue)
    case .pages: PageStatus.allCases.map(\.rawValue)
    }
  }

  func statusSystemImage(_ rawValue: String) -> String {
    switch self {
    case .diamonds: DiamondStatus.systemImage(for: rawValue)
    case .books: BookStatus.systemImage(for: rawValue)
    case .pages: PageStatus.systemImage(for: rawValue)
    }
  }

  /// Pages are created from their book, so they have no create target.
  var createTarget: CreateTarget? {
    switch self {
    case .diamonds: .diamond
    case .books: .book
    case .pages: nil
    }
  }

  func statusLabel(_ rawValue: String) -> String {
    switch self {
    case .diamonds: DiamondStatus.label(for: rawValue)
    case .books: BookStatus.label(for: rawValue)
    case .pages: PageStatus.label(for: rawValue)
    }
  }

  /// Shelf order when browsing everything: active work first, then what's
  /// waiting, then finished or gone.
  var shelfOrder: [String] {
    switch self {
    case .diamonds:
      [DiamondStatus.progress, .onhold, .kitted, .stash, .purchased, .wishlist,
       .completed, .archived, .destashed].map(\.rawValue)
    case .books:
      [BookStatus.inProgress, .inStash, .purchased, .wishlist, .completed, .archived,
       .destashed].map(\.rawValue)
    case .pages:
      [PageStatus.inProgress, .onHold, .paletteChosen, .notStarted, .completed].map(\.rawValue)
    }
  }

  var sortOptions: [LibrarySort] {
    switch self {
    case .diamonds:
      [.recentlyUpdated, .titleAscending, .titleDescending]
    case .books:
      [.recentlyUpdated, .titleAscending, .titleDescending]
    case .pages:
      [.recentlyUpdated, .pageAscending, .pageDescending]
    }
  }
}

extension LibraryItem {
  var section: LibrarySection {
    switch self {
    case .diamond: .diamonds
    case .book: .books
    case .page: .pages
    }
  }

  /// Owned by the user in that craft; pages belong through an owned book.
  func belongs(
    to section: LibrarySection, userID: String, bookTitles: [String: String]
  ) -> Bool {
    switch (section, self) {
    case (.diamonds, .diamond(let project)): project.user == userID
    case (.books, .book(let book)): book.user == userID
    case (.pages, .page(let page)): bookTitles[page.book] != nil
    default: false
    }
  }
}

extension LibrarySession {
  func ownedBookTitles() -> [String: String] {
    var titles: [String: String] = [:]
    for item in items {
      if case .book(let book) = item, book.user == userID {
        titles[book.id] = book.title
      }
    }
    return titles
  }

  /// On-device counts per status for one craft, so sidebar shelves work offline.
  func shelfCounts(for section: LibrarySection) -> [String: Int] {
    let bookTitles = section == .pages ? ownedBookTitles() : [:]
    return items.reduce(into: [:]) { counts, item in
      if item.belongs(to: section, userID: userID, bookTitles: bookTitles) {
        counts[item.status, default: 0] += 1
      }
    }
  }
}

/// How a Library screen is reached. iPhone and the collapsed iPad tab bar
/// browse every craft; iPad sidebar rows pin one craft or one of its shelves;
/// Search has its own tab.
enum LibraryPresentation: Hashable {
  case browse
  case craft(LibrarySection)
  case shelf(LibrarySection, status: String)
  case search

  var title: String {
    switch self {
    case .browse: "Library"
    case .craft(let section): section.pickerTitle
    case .shelf(let section, let status): section.statusLabel(status)
    case .search: "Search"
    }
  }

  var pinnedSection: LibrarySection? {
    switch self {
    case .craft(let section), .shelf(let section, _): section
    case .browse, .search: nil
    }
  }

  var showsCraftPicker: Bool {
    pinnedSection == nil
  }

  var showsStatusChips: Bool {
    switch self {
    case .browse, .craft: true
    case .shelf, .search: false
    }
  }

  var isSearchable: Bool {
    self == .search
  }

  func accepts(_ request: LibraryRequest) -> Bool {
    switch self {
    case .browse: true
    case .craft(let section): section == request.section
    case .shelf(let section, let status): section == request.section && status == request.status
    case .search: false
    }
  }
}

enum LibrarySort: String, CaseIterable, Identifiable {
  case recentlyUpdated
  case titleAscending
  case titleDescending
  case pageAscending
  case pageDescending

  var id: Self { self }

  var title: String {
    switch self {
    case .recentlyUpdated: "Recently updated"
    case .titleAscending: "Title A to Z"
    case .titleDescending: "Title Z to A"
    case .pageAscending: "Page number ascending"
    case .pageDescending: "Page number descending"
    }
  }

  func query(for section: LibrarySection) -> String {
    switch (self, section) {
    case (.recentlyUpdated, _): "-updated"
    case (.titleAscending, .diamonds): "+title_sort"
    case (.titleDescending, .diamonds): "-title_sort"
    case (.titleAscending, .books): "+title"
    case (.titleDescending, .books): "-title"
    case (.pageAscending, .pages): "+page_number"
    case (.pageDescending, .pages): "-page_number"
    default: "-updated"
    }
  }
}

struct LibraryShelf: Identifiable {
  let status: String
  var items: [LibraryItem]

  var id: String { status }
}

struct LibraryRequest: Equatable {
  let id = UUID()
  let section: LibrarySection
  let status: String
}

@MainActor
@Observable
final class LibraryModel {
  let library: LibrarySession
  var client: PocketBaseClient { library.client }
  var userID: String { library.userID }

  var section = LibrarySection.diamonds
  var searchText = ""
  private(set) var committedSearch = ""
  var statusFilter: String?
  var sort = LibrarySort.recentlyUpdated
  var isLoading = false
  var hasLoaded = false
  var errorMessage: String?
  var isMutating = false
  var mutationError: String?

  private(set) var displayedItems: [LibraryItem] = []
  private(set) var shelfCounts: [String: Int] = [:]
  private var currentPage = 0
  private var totalPages = 0
  private var generation = 0
  private var listingEpoch = 0
  var onSessionExpired: (@MainActor @Sendable () async -> Void)?

  init(library: LibrarySession) {
    self.library = library
  }

  var items: [LibraryItem] {
    displayedItems
  }

  /// Browsing everything groups the listing into status shelves; a status
  /// filter or a search lists flat.
  var isShelved: Bool {
    statusFilter == nil && committedSearch.isEmpty
  }

  /// Loaded items grouped by status. Shelved listings sort by shelf first, so
  /// each shelf is one contiguous run even across pages.
  var shelves: [LibraryShelf] {
    var shelves: [LibraryShelf] = []
    for item in displayedItems {
      if shelves.last?.status == item.status {
        shelves[shelves.count - 1].items.append(item)
      } else {
        shelves.append(LibraryShelf(status: item.status, items: [item]))
      }
    }
    return shelves
  }

  var canLoadMore: Bool {
    currentPage < totalPages
  }

  /// Observed by Library's load task. Section, status, sort, and the committed
  /// search query are included so browsing changes reload; `listingEpoch`
  /// changes when a handoff clears search without changing the other fields.
  var listingIdentity: String {
    "\(section.rawValue)|\(statusFilter ?? "")|\(sort.rawValue)|\(committedSearch)|\(listingEpoch)"
  }

  func apply(_ request: LibraryRequest) {
    select(request.section)
    searchText = ""
    committedSearch = ""
    statusFilter = request.status
    sort = .recentlyUpdated
    listingEpoch += 1
  }

  func select(_ section: LibrarySection) {
    guard self.section != section else {
      return
    }
    self.section = section
    searchText = ""
    committedSearch = ""
    statusFilter = nil
    sort = .recentlyUpdated
  }

  func clearSearch() async {
    guard !searchText.isEmpty || !committedSearch.isEmpty else {
      return
    }
    searchText = ""
    committedSearch = ""
    await load()
  }

  /// Keeps Library on an enabled craft when preferences load or change.
  func align(to verticals: VerticalPreferences) {
    let available = LibrarySection.available(for: verticals)
    if !available.contains(section), let first = available.first {
      select(first)
    }
  }

  /// Reloads the listing after a save, then returns the record that should stay
  /// selected. Filtered-out saves return `nil`; records that still belong but
  /// are absent from page 1 keep the saved snapshot, including any expand the
  /// listing already had. Page writes omit the parent book, and page-number
  /// sort often leaves the edited page off page 1.
  func selection(
    afterSaving item: LibraryItem, previousSelection: LibraryItem? = nil
  ) async -> LibraryItem? {
    let snapshot = item.retainingListingContext(
      from: previousSelection ?? items.first(where: { $0.id == item.id }))
    await load()
    if let refreshed = items.first(where: { $0.id == item.id }) {
      return refreshed
    }
    return matchesCurrentListing(snapshot, bookTitles: ownedBookTitles()) ? snapshot : nil
  }

  func acceptSavedBook(_ book: ColoringBookRecord) {
    let saved = LibraryItem.book(book)
    guard let index = displayedItems.firstIndex(where: { $0.id == saved.id }) else { return }
    let updated = saved
      .retainingListingContext(from: displayedItems[index])
    if matchesCurrentListing(updated, bookTitles: ownedBookTitles()) {
      displayedItems[index] = updated
      displayedItems.sort(by: precedes)
    } else {
      displayedItems.remove(at: index)
    }
  }

  func load(reset: Bool = true) async {
    if !reset, isLoading || !canLoadMore {
      return
    }

    if reset {
      committedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
      generation += 1
    }
    let requestGeneration = generation
    let requestedSection = section
    let requestedPage = reset ? 1 : currentPage + 1

    isLoading = true
    errorMessage = nil
    defer {
      if requestGeneration == generation {
        isLoading = false
        hasLoaded = true
      }
    }

    do {
      if reset { try await library.loadLocal() }
      guard requestGeneration == generation, section == requestedSection else { return }
      if !library.hasSnapshot && library.items.isEmpty {
        displayedItems = []
        return
      }
      let bookTitles = ownedBookTitles()
      let matching = library.items.filter { matchesCurrentListing($0, bookTitles: bookTitles) }
        .sorted(by: precedes)
      shelfCounts = matching.reduce(into: [:]) { $0[$1.status, default: 0] += 1 }
      totalPages = (matching.count + Self.pageSize - 1) / Self.pageSize
      currentPage = min(requestedPage, totalPages)
      displayedItems = Array(matching.prefix(requestedPage * Self.pageSize))
    } catch APIError.cancelled {
      return
    } catch APIError.unauthenticated {
      guard requestGeneration == generation else {
        return
      }
      errorMessage = APIError.unauthenticated.libraryMessage
      await onSessionExpired?()
    } catch {
      guard requestGeneration == generation else {
        return
      }
      errorMessage = error.libraryMessage
    }
  }

  func refresh() async {
    do {
      try await library.refresh()
      await load()
    } catch {
      errorMessage = error.libraryMessage
    }
  }

  func delete(_ item: LibraryItem) async {
    guard !isMutating else {
      return
    }
    let collection: String
    let recordID: String
    switch item {
    case .diamond(let project):
      collection = "projects"
      recordID = project.id
    case .book(let book):
      collection = "coloring_books"
      recordID = book.id
    case .page:
      // ponytail: pages are deleted through their book, so no detail view wires
      // up onDelete for one. Required for exhaustiveness, not dead weight.
      return
    }

    isMutating = true
    mutationError = nil
    defer { isMutating = false }

    do {
      try await library.delete(collection: collection, id: recordID)
      await load()
    } catch {
      if error as? APIError == .offline || error as? APIError == .server {
        do {
          try await library.refreshFromServer()
          await load()
          if !library.items.contains(where: { $0.id == item.id }) {
            return
          }
          mutationError = "The item is still in your account. Try deleting it again."
        } catch {
          mutationError =
            "Delete status is unknown. Reconnect and refresh your library before trying again."
        }
      } else {
        mutationError = error.userMessage(
          permission: "Your account does not have permission to delete this item.",
          fallback: "The item could not be deleted. Try again."
        )
      }
    }
  }

  private static let pageSize = 30

  private func ownedBookTitles() -> [String: String] {
    section == .pages ? library.ownedBookTitles() : [:]
  }

  private func matchesCurrentListing(
    _ item: LibraryItem, bookTitles: [String: String]
  ) -> Bool {
    guard item.belongs(to: section, userID: userID, bookTitles: bookTitles) else {
      return false
    }

    if let statusFilter, item.status != statusFilter {
      return false
    }

    let search = committedSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !search.isEmpty else {
      return true
    }

    switch item {
    case .diamond(let project):
      return matchesSearch(
        search,
        [
          project.title,
          project.expand?.artist?.name,
          project.expand?.company?.name,
        ])
    case .book(let book):
      return matchesSearch(
        search,
        [
          book.title,
          book.expand?.publisher?.name,
          book.expand?.illustrator?.name,
        ])
    case .page(let page):
      if let pageNumber = Int(search) {
        return page.pageNumber == pageNumber
      }
      let bookTitle = page.expand?.book?.title ?? bookTitles[page.book] ?? ""
      return bookTitle.localizedCaseInsensitiveContains(search)
    }
  }

  private func matchesSearch(_ search: String, _ values: [String?]) -> Bool {
    values.contains { ($0 ?? "").localizedCaseInsensitiveContains(search) }
  }

  private func precedes(_ lhs: LibraryItem, _ rhs: LibraryItem) -> Bool {
    if isShelved, lhs.status != rhs.status {
      let order = section.shelfOrder
      let left = order.firstIndex(of: lhs.status) ?? order.count
      let right = order.firstIndex(of: rhs.status) ?? order.count
      return left == right ? lhs.status < rhs.status : left < right
    }
    switch sort {
    case .recentlyUpdated:
      return lhs.updated == rhs.updated ? lhs.recordID < rhs.recordID : lhs.updated > rhs.updated
    case .titleAscending, .titleDescending:
      let comparison = lhs.title.localizedStandardCompare(rhs.title)
      return comparison == .orderedSame ? lhs.recordID < rhs.recordID
        : comparison == (sort == .titleAscending ? .orderedAscending : .orderedDescending)
    case .pageAscending, .pageDescending:
      guard case .page(let left) = lhs, case .page(let right) = rhs else { return false }
      return left.pageNumber == right.pageNumber ? left.id < right.id
        : (sort == .pageAscending ? left.pageNumber < right.pageNumber
          : left.pageNumber > right.pageNumber)
    }
  }
}

extension Error {
  fileprivate var libraryMessage: String {
    switch self as? APIError {
    case .offline:
      "You’re offline. Reconnect and try again."
    case .forbidden:
      "Your account does not have permission to view this collection."
    case .unauthenticated:
      "Your session has expired. Sign in again."
    default:
      "Your library is unavailable right now. Try again shortly."
    }
  }
}
