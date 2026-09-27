import Foundation
import Observation

enum BookPageFilter: String, CaseIterable, Identifiable {
  case all
  case inProgress = "in_progress"
  case completed

  var id: Self { self }

  var title: String {
    switch self {
    case .all: "All"
    case .inProgress: "In progress"
    case .completed: "Completed"
    }
  }

  var status: String? {
    self == .all ? nil : rawValue
  }
}

enum DetailUnresolvedWriteState: Equatable {
  case needsRefresh
  case refreshed
}

@MainActor
@Observable
final class LibraryItemDetailModel {
  let library: LibrarySession
  var client: PocketBaseClient { library.client }
  var userID: String { library.userID }

  private(set) var item: LibraryItem
  private(set) var progressNotes: [DiamondProgressNoteRecord] = []
  private(set) var bookPages: [ColoringPageRecord] = []
  var needsBookPageRefresh = false
  private(set) var canLoadMoreBookPages = false
  private(set) var canLoadMoreProgressNotes = false

  var bookPageFilter = BookPageFilter.all
  var isLoading = false
  private(set) var hasLoaded = false
  var isLoadingMore = false
  var isMutating = false
  var errorMessage: String?
  var mutationErrorMessage: String?
  private(set) var statusErrorMessage: String?
  private(set) var unresolvedWriteState: DetailUnresolvedWriteState?
  private(set) var unresolvedStatusWrite = false

  private var bookPagesPage = 0
  private var bookPagesTotalPages = 0
  private var progressNotesPage = 0
  private var progressNotesTotalPages = 0
  private var generation = 0
  private var unresolvedDiamondWriteIncludesPhoto = false
  private static let bookPagesPerPage = 24
  static let projectExpand = "company,artist,project_tags_via_project.tag"

  init(item: LibraryItem, library: LibrarySession) {
    self.item = item
    self.library = library
  }

  @discardableResult
  func load(preservingLoadedBookPages: Bool = false) async -> Bool {
    generation += 1
    isLoading = true
    errorMessage = nil
    defer {
      isLoading = false
      hasLoaded = true
    }

    do {
      try await library.loadLocal()
      if let current = library.items.first(where: { $0.id == item.id }) {
        item = current.retainingListingContext(from: item)
      } else if library.hasSnapshot {
        errorMessage = APIError.notFound.detailLoadMessage
        return false
      }
      switch item {
      case .diamond(let project):
        let matching = library.progressNotes.filter { $0.project == project.id }
          .sorted { Self.progressNote($0, precedes: $1) }
        progressNotesPage = 1
        progressNotesTotalPages = (matching.count + 19) / 20
        progressNotes = Array(matching.prefix(20))
        canLoadMoreProgressNotes = progressNotesPage < progressNotesTotalPages
      case .book(let book):
        let pagesToShow = preservingLoadedBookPages ? max(bookPagesPage, 1) : 1
        projectBookPages(bookID: book.id, pagesToShow: pagesToShow)
      case .page:
        break
      }
      return true
    } catch APIError.cancelled {
      return false
    } catch {
      errorMessage = error.detailLoadMessage
      return false
    }
  }

  func refresh() async {
    do { try await library.refresh() } catch { errorMessage = error.detailLoadMessage }
    await load(preservingLoadedBookPages: true)
  }

  func setBookPageFilter(_ filter: BookPageFilter) async {
    guard bookPageFilter != filter else { return }
    bookPageFilter = filter
    await reloadBookPages()
  }

  func reloadBookPages() async {
    guard case .book(let book) = item else { return }
    projectBookPages(bookID: book.id, pagesToShow: 1)
  }

  func loadMoreBookPages() async {
    guard case .book(let book) = item, canLoadMoreBookPages else { return }
    projectBookPages(bookID: book.id, pagesToShow: bookPagesPage + 1)
  }

  func loadMoreProgressNotes() async {
    guard case .diamond(let project) = item, canLoadMoreProgressNotes else { return }
    let matching = library.progressNotes.filter { $0.project == project.id }
      .sorted { Self.progressNote($0, precedes: $1) }
    progressNotesPage += 1
    progressNotes = Array(matching.prefix(progressNotesPage * 20))
    progressNotesTotalPages = (matching.count + 19) / 20
    canLoadMoreProgressNotes = progressNotesPage < progressNotesTotalPages
  }

  private func projectBookPages(bookID: String, pagesToShow: Int) {
    let matching = library.items.compactMap { item -> ColoringPageRecord? in
      guard case .page(let page) = item, page.book == bookID,
        bookPageFilter.status == nil || page.status == bookPageFilter.status else { return nil }
      return page
    }.sorted { $0.pageNumber == $1.pageNumber ? $0.id < $1.id : $0.pageNumber < $1.pageNumber }
    bookPagesPage = pagesToShow
    bookPagesTotalPages = (matching.count + Self.bookPagesPerPage - 1) / Self.bookPagesPerPage
    bookPages = Array(matching.prefix(pagesToShow * Self.bookPagesPerPage))
    canLoadMoreBookPages = bookPagesPage < bookPagesTotalPages
  }

  func acceptSaved(_ saved: LibraryItem) async {
    item = saved.retainingListingContext(from: item)
    await load()
  }

  func deleteItem() async -> Bool {
    guard !isMutating else { return false }
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
      return false
    }

    isMutating = true
    mutationErrorMessage = nil
    statusErrorMessage = nil
    defer { isMutating = false }
    do {
      try await library.delete(collection: collection, id: recordID)
      return true
    } catch {
      mutationErrorMessage = error.userMessage(
        permission: "Your account does not have permission to delete this item.",
        fallback: "The item could not be deleted. Try again."
      )
      return false
    }
  }

  /// Plain status PATCH, matching the web. Dates stay as the user set them.
  func setStatus(_ status: String) async -> Bool {
    guard !isMutating, unresolvedWriteState == nil, item.status != status else { return false }
    isMutating = true
    mutationErrorMessage = nil
    statusErrorMessage = nil
    defer { isMutating = false }
    let patch = ["status": status]
    do {
      let saved: LibraryItem
      switch item {
      case .diamond(let project):
        saved = .diamond(try await library.update(collection: "projects", id: project.id, body: patch))
      case .book(let book):
        saved = .book(
          try await library.update(collection: "coloring_books", id: book.id, body: patch))
      case .page:
        return false
      }
      item = saved.retainingListingContext(from: item)
      await load()
      return true
    } catch APIError.offline, APIError.server, APIError.decoding, APIError.cancelled {
      unresolvedStatusWrite = true
      unresolvedWriteState = .needsRefresh
      _ = await reconcileUnresolvedWrite()
      return false
    } catch {
      statusErrorMessage = error.userMessage(
        permission: "Your account does not have permission to change the status.",
        fallback: "The status could not be changed. Try again."
      )
      return false
    }
  }

  func addDiamondProgressNote(
    content: String,
    date: Date,
    photo: ProcessedDetailPhoto?
  ) async -> Bool {
    guard case .diamond(let project) = item,
      !isMutating,
      unresolvedWriteState == nil
    else {
      return false
    }
    isMutating = true
    mutationErrorMessage = nil
    statusErrorMessage = nil
    defer { isMutating = false }

    var files: [PocketBaseMultipartFile] = []
    if let photo {
      files.append(
        PocketBaseMultipartFile(
          fieldName: "image",
          fileName: photo.fileName,
          contentType: photo.contentType,
          data: photo.data
        ))
    }
    let form = PocketBaseMultipartForm(
      fields: [
        "project": project.id,
        "content": content.trimmingCharacters(in: .whitespacesAndNewlines),
        "date": Self.dateOnlyString(from: date),
      ],
      files: files
    )

    do {
      let saved: DiamondProgressNoteRecord = try await library.create(
        collection: "progress_notes",
        multipart: form
      )
      mergeProgressNote(saved)
      return true
    } catch APIError.offline, APIError.server, APIError.cancelled {
      unresolvedDiamondWriteIncludesPhoto = photo != nil
      unresolvedWriteState = .needsRefresh
      _ = await reconcileUnresolvedWrite()
      return false
    } catch {
      mutationErrorMessage = error.userMessage(
        permission: "Your account does not have permission to add a progress note.",
        fallback: "The progress note could not be added. Try again."
      )
      return false
    }
  }

  func appendPagePhoto(_ photo: ProcessedDetailPhoto) async -> Bool {
    guard case .page(let page) = item,
      !isMutating,
      unresolvedWriteState == nil
    else {
      return false
    }
    isMutating = true
    mutationErrorMessage = nil
    statusErrorMessage = nil
    defer { isMutating = false }

    let form = PocketBaseMultipartForm(
      files: [
        PocketBaseMultipartFile(
          fieldName: "photos+",
          fileName: photo.fileName,
          contentType: photo.contentType,
          data: photo.data
        )
      ]
    )
    do {
      let saved: ColoringPageRecord = try await library.update(
        collection: "coloring_pages",
        id: page.id,
        multipart: form
      )
      item = .page(saved.withExpand(page.expand))
      await load()
      return true
    } catch APIError.offline, APIError.server, APIError.cancelled {
      unresolvedWriteState = .needsRefresh
      _ = await reconcileUnresolvedWrite()
      return false
    } catch {
      mutationErrorMessage = error.userMessage(
        permission: "Your account does not have permission to add a photo.",
        fallback: "The photo could not be added. Try again."
      )
      return false
    }
  }

  @discardableResult
  func refreshUnresolvedWriteStatus() async -> Bool {
    guard unresolvedWriteState != nil, !isMutating else { return false }
    isMutating = true
    defer { isMutating = false }

    return await reconcileUnresolvedWrite()
  }

  func clearUnresolvedWriteRecovery() {
    guard unresolvedWriteState == .refreshed else { return }
    unresolvedWriteState = nil
    unresolvedDiamondWriteIncludesPhoto = false
    unresolvedStatusWrite = false
    mutationErrorMessage = nil
  }

  private func reconcileUnresolvedWrite() async -> Bool {
    let didRefresh = await load()
    if didRefresh {
      unresolvedWriteState = .refreshed
      if unresolvedStatusWrite {
        mutationErrorMessage =
          "The status response was lost. Review the refreshed status before changing it again."
        return true
      }
      switch item {
      case .diamond:
        mutationErrorMessage =
          unresolvedDiamondWriteIncludesPhoto
          ? "The save response was lost. Review the refreshed progress notes and photos before adding another note."
          : "The save response was lost. Review the refreshed progress notes before adding another note."
      case .page:
        mutationErrorMessage =
          "The upload response was lost. Review the refreshed photos before starting a new upload."
      case .book:
        mutationErrorMessage = "The save response was lost. Review the refreshed item."
      }
      return true
    }

    unresolvedWriteState = .needsRefresh
    if unresolvedStatusWrite {
      mutationErrorMessage =
        "Status is unknown because the item could not be refreshed. Refresh status before changing it again."
      return false
    }
    switch item {
    case .diamond:
      mutationErrorMessage =
        "Progress note status is unknown because the project could not be refreshed. Refresh status before adding another note."
    case .page:
      mutationErrorMessage =
        "Upload status is unknown because the photos could not be refreshed. Refresh status before starting another upload."
    case .book:
      mutationErrorMessage = "Save status is unknown. Refresh the item before trying again."
    }
    return false
  }

  private func mergeProgressNote(_ saved: DiamondProgressNoteRecord) {
    progressNotes.removeAll { $0.id == saved.id }
    let insertionIndex =
      progressNotes.firstIndex {
        Self.progressNote(saved, precedes: $0)
      } ?? progressNotes.endIndex
    progressNotes.insert(saved, at: insertionIndex)
  }

  private static func progressNote(
    _ lhs: DiamondProgressNoteRecord,
    precedes rhs: DiamondProgressNoteRecord
  ) -> Bool {
    if lhs.date != rhs.date {
      return lhs.date > rhs.date
    }
    return lhs.created > rhs.created
  }

  private static func dateOnlyString(from date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0
    )
  }
}


extension Error {
  fileprivate var detailLoadMessage: String {
    switch self as? APIError {
    case .offline:
      APIError.offlineMessage
    case .unauthenticated:
      APIError.sessionExpiredMessage
    case .forbidden:
      "Your account does not have permission to view this item."
    case .notFound:
      "This item no longer exists."
    default:
      "This item could not be loaded. Try again."
    }
  }
}
