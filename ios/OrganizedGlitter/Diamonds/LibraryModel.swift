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
    case .diamonds: "diamond"
    case .books: "books.vertical"
    case .pages: "doc.richtext"
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
    case .diamonds:
      [
        "wishlist", "purchased", "stash", "kitted", "progress", "onhold", "completed", "archived",
        "destashed",
      ]
    case .books:
      ["wishlist", "purchased", "in_stash", "in_progress", "completed", "archived", "destashed"]
    case .pages:
      ["not_started", "palette_chosen", "in_progress", "on_hold", "completed"]
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

struct LibraryRequest: Equatable {
  let id = UUID()
  let section: LibrarySection
  let status: String
}

@MainActor
@Observable
final class LibraryModel {
  let client: PocketBaseClient
  let userID: String

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

  private(set) var projects: [DiamondProjectRecord] = []
  private(set) var books: [ColoringBookRecord] = []
  private(set) var pages: [ColoringPageRecord] = []
  private var currentPage = 0
  private var totalPages = 0
  private var generation = 0
  private var listingEpoch = 0
  var onSessionExpired: (@MainActor @Sendable () async -> Void)?

  init(client: PocketBaseClient, userID: String) {
    self.client = client
    self.userID = userID
  }

  var items: [LibraryItem] {
    switch section {
    case .diamonds:
      projects.map(LibraryItem.diamond)
    case .books:
      books.map(LibraryItem.book)
    case .pages:
      pages.map(LibraryItem.page)
    }
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
    return matchesCurrentListing(snapshot) ? snapshot : nil
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
    let requestedSort = sort
    let requestedSearch = committedSearch
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
      switch requestedSection {
      case .diamonds:
        let result: RecordList<DiamondProjectRecord> = try await client.list(
          collection: "projects",
          page: requestedPage,
          filter: filter(for: requestedSection, search: requestedSearch),
          sort: requestedSort.query(for: requestedSection),
          expand: "company,artist"
        )
        guard requestGeneration == generation, section == requestedSection else {
          return
        }
        projects = reset ? result.items : projects + result.items
        applyPagination(result)
      case .books:
        let result: RecordList<ColoringBookRecord> = try await client.list(
          collection: "coloring_books",
          page: requestedPage,
          filter: filter(for: requestedSection, search: requestedSearch),
          sort: requestedSort.query(for: requestedSection),
          expand: "publisher,illustrator"
        )
        guard requestGeneration == generation, section == requestedSection else {
          return
        }
        books = reset ? result.items : books + result.items
        applyPagination(result)
      case .pages:
        let result: RecordList<ColoringPageRecord> = try await client.list(
          collection: "coloring_pages",
          page: requestedPage,
          filter: filter(for: requestedSection, search: requestedSearch),
          sort: requestedSort.query(for: requestedSection),
          expand: "book"
        )
        guard requestGeneration == generation, section == requestedSection else {
          return
        }
        pages = reset ? result.items : pages + result.items
        applyPagination(result)
      }
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
      try await client.delete(collection: collection, id: recordID)
      await load()
    } catch {
      if error as? APIError == .offline || error as? APIError == .server {
        await load()
        if !items.contains(where: { $0.id == item.id }) {
          return
        }
        mutationError =
          "Delete status is unknown. The library was refreshed; check the item before trying again."
      } else {
        mutationError = error.userMessage(
          permission: "Your account does not have permission to delete this item.",
          fallback: "The item could not be deleted. Try again."
        )
      }
    }
  }

  private func filter(for section: LibrarySection, search: String? = nil) -> String {
    var filters = [
      PocketBaseFilter.equals(section == .pages ? .bookUser : .user, userID)
    ]

    let search = (search ?? committedSearch).trimmingCharacters(in: .whitespacesAndNewlines)
    if !search.isEmpty {
      if section == .pages, let pageNumber = Int(search) {
        filters.append(PocketBaseFilter.equals(.pageNumber, pageNumber))
      } else {
        filters.append(
          PocketBaseFilter.any(
            searchFields(for: section).map { PocketBaseFilter.contains($0, search) })
        )
      }
    }

    if let statusFilter {
      filters.append(PocketBaseFilter.equals(.status, statusFilter))
    }
    return PocketBaseFilter.all(filters)
  }

  private func matchesCurrentListing(_ item: LibraryItem) -> Bool {
    switch (section, item) {
    case (.diamonds, .diamond), (.books, .book), (.pages, .page):
      break
    default:
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
      guard let bookTitle = page.expand?.book?.title else {
        return true
      }
      return bookTitle.localizedCaseInsensitiveContains(search)
    }
  }

  private func searchFields(for section: LibrarySection) -> [PocketBaseFilter.Field] {
    switch section {
    case .diamonds: [.title, .artistName, .companyName]
    case .books: [.title, .publisherName, .illustratorName]
    case .pages: [.bookTitle]
    }
  }

  private func matchesSearch(_ search: String, _ values: [String?]) -> Bool {
    values.contains { ($0 ?? "").localizedCaseInsensitiveContains(search) }
  }

  private func applyPagination<Record>(_ result: RecordList<Record>) {
    currentPage = result.page
    totalPages = result.totalPages
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
