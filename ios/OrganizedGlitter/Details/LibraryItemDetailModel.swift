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

extension LibraryItemDetailModel: Identifiable {}

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
  private(set) var progressNotes: [ProgressNoteItem] = []
  /// The note the server most recently confirmed from this model, for the saved-entry reveal.
  private(set) var lastAddedProgressNoteID: String?
  private(set) var statusSaveRevision = 0
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
  private(set) var editErrorMessage: String?
  private(set) var unresolvedWriteState: DetailUnresolvedWriteState?
  private(set) var unresolvedStatusWrite = false

  private var bookPagesPage = 0
  private var bookPagesTotalPages = 0
  private var progressNotesPage = 0
  private var progressNotesTotalPages = 0
  private var generation = 0
  private var unresolvedNoteWriteIncludesPhoto = false
  private var unresolvedNoteCreate = false
  private var unresolvedNoteAction: String?
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
        projectProgressNotes(projectID: project.id, pagesToShow: max(progressNotesPage, 1))
      case .book(let book):
        let pagesToShow = preservingLoadedBookPages ? max(bookPagesPage, 1) : 1
        projectBookPages(bookID: book.id, pagesToShow: pagesToShow)
      case .page(let page):
        pageProgressNotes(pageID: page.id, pagesToShow: max(progressNotesPage, 1))
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
    library.captureAnalytics(.pagesFilterChanged, properties: ["record_type": "coloring_pages", "filter_active": filter != .all])
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
    guard canLoadMoreProgressNotes else { return }
    switch item {
    case .diamond(let project):
      projectProgressNotes(projectID: project.id, pagesToShow: progressNotesPage + 1)
    case .page(let page):
      pageProgressNotes(pageID: page.id, pagesToShow: progressNotesPage + 1)
    case .book:
      break
    }
  }

  private func projectProgressNotes(projectID: String, pagesToShow: Int) {
    let matching = library.progressNotes.filter { $0.project == projectID }
      .map(ProgressNoteItem.diamond)
      .sorted { Self.progressNote($0, precedes: $1) }
    showProgressNotes(matching, pagesToShow: pagesToShow)
  }

  private func pageProgressNotes(pageID: String, pagesToShow: Int) {
    let matching = library.coloringPageProgressNotes.filter { $0.page == pageID }
      .map(ProgressNoteItem.coloring)
      .sorted { Self.progressNote($0, precedes: $1) }
    showProgressNotes(matching, pagesToShow: pagesToShow)
  }

  private func showProgressNotes(_ matching: [ProgressNoteItem], pagesToShow: Int) {
    progressNotesPage = pagesToShow
    progressNotesTotalPages = (matching.count + 19) / 20
    progressNotes = Array(matching.prefix(progressNotesPage * 20))
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
    editErrorMessage = nil
    defer { isMutating = false }
    do {
      try await library.delete(collection: collection, id: recordID)
      return true
    } catch {
      mutationErrorMessage = error.userMessage(
        permission: "Your account does not have permission to delete this item.",
        offline: APIError.deleteNeedsConnectionMessage,
        fallback: "The item could not be deleted. Try again."
      )
      return false
    }
  }

  /// Plain status PATCH, matching the web. Project and book dates stay as the
  /// user set them; the server fills page started/completed dates from status.
  func setStatus(_ status: String) async -> Bool {
    guard !isMutating, unresolvedWriteState == nil, item.status != status else { return false }
    isMutating = true
    mutationErrorMessage = nil
    editErrorMessage = nil
    defer { isMutating = false }
    do {
      item = try await saveLocally(["status": status]).retainingListingContext(from: item)
      statusSaveRevision += 1
      await load()
      return true
    } catch APIError.offline, APIError.server, APIError.decoding, APIError.cancelled {
      unresolvedStatusWrite = true
      unresolvedWriteState = .needsRefresh
      _ = await reconcileUnresolvedWrite()
      return false
    } catch {
      editErrorMessage = error.userMessage(
        permission: "Your account does not have permission to change the status.",
        fallback: "The status could not be changed. Try again."
      )
      return false
    }
  }

  /// In-place edits of offline-capable fields, queued locally like status.
  @discardableResult
  func updateFields(_ patch: [String: String]) async -> Bool {
    guard !isMutating, unresolvedWriteState == nil, !patch.isEmpty else { return false }
    isMutating = true
    editErrorMessage = nil
    defer { isMutating = false }
    do {
      item = try await saveLocally(patch).retainingListingContext(from: item)
      await load()
      return true
    } catch APIError.cancelled {
      return false
    } catch {
      editErrorMessage = error.userMessage(
        permission: "Your account does not have permission to change this item.",
        fallback: "The change could not be saved. Try again."
      )
      return false
    }
  }

  /// `nil` clears the date. PocketBase stores these as `yyyy-MM-dd`.
  @discardableResult
  func setDate(_ field: String, to date: Date?) async -> Bool {
    var patch = [field: date.map { DetailDateOnly.string(from: $0) } ?? ""]
    if case .page = item, field == "completed_at", date != nil {
      patch["status"] = "completed"
    }
    return await updateFields(patch)
  }

  private func saveLocally(_ patch: [String: String]) async throws -> LibraryItem {
    switch item {
    case .diamond(let project):
      .diamond(try await library.update(collection: "projects", id: project.id, body: patch))
    case .book(let book):
      .book(try await library.update(collection: "coloring_books", id: book.id, body: patch))
    case .page(let page):
      .page(try await library.update(collection: "coloring_pages", id: page.id, body: patch))
    }
  }

  func addProgressNote(
    content: String,
    date: Date,
    photo: ProcessedDetailPhoto?
  ) async -> Bool {
    guard !isMutating,
      unresolvedWriteState == nil
    else {
      return false
    }
    let createNote: @MainActor (PocketBaseMultipartForm) async throws -> ProgressNoteItem
    let parent: (String, String)
    switch item {
    case .diamond(let project):
      parent = ("project", project.id)
      createNote = { form in
        let note: DiamondProgressNoteRecord = try await self.library.create(
          collection: "progress_notes", multipart: form)
        return .diamond(note)
      }
    case .page(let page):
      parent = ("page", page.id)
      createNote = { form in
        let note: ColoringProgressNoteRecord = try await self.library.create(
          collection: "coloring_page_progress_notes", multipart: form)
        return .coloring(note)
      }
    case .book:
      return false
    }
    isMutating = true
    mutationErrorMessage = nil
    editErrorMessage = nil
    unresolvedNoteCreate = true
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
        parent.0: parent.1,
        "content": content.trimmingCharacters(in: .whitespacesAndNewlines),
        "date": DetailDateOnly.string(from: date),
      ],
      files: files
    )

    do {
      let saved = try await createNote(form)
      mergeProgressNote(saved)
      lastAddedProgressNoteID = saved.recordID
      unresolvedNoteCreate = false
      return true
    } catch APIError.offline, APIError.server, APIError.cancelled {
      unresolvedNoteWriteIncludesPhoto = photo != nil
      unresolvedWriteState = .needsRefresh
      _ = await reconcileUnresolvedWrite()
      return false
    } catch {
      unresolvedNoteCreate = false
      mutationErrorMessage = error.userMessage(
        permission: "Your account does not have permission to add a progress note.",
        offline: APIError.needsConnection("Adding a progress note"),
        fallback: "The progress note could not be added. Try again."
      )
      return false
    }
  }

  func updateProgressNote(_ note: ProgressNoteItem, content: String, date: Date) async -> String? {
    guard !isMutating, unresolvedWriteState == nil,
      progressNotes.contains(where: { $0.id == note.id })
    else { return "This note is unavailable. Refresh and try again." }
    isMutating = true
    defer { isMutating = false }
    let fields = [
      "content": content.trimmingCharacters(in: .whitespacesAndNewlines),
      "date": DetailDateOnly.string(from: date),
    ]
    do {
      let saved: ProgressNoteItem
      switch note {
      case .diamond:
        let updated: DiamondProgressNoteRecord = try await library.updateOnline(
          collection: note.collection, id: note.recordID, body: fields)
        saved = .diamond(updated)
      case .coloring:
        let updated: ColoringProgressNoteRecord = try await library.updateOnline(
          collection: note.collection, id: note.recordID, body: fields)
        saved = .coloring(updated)
      }
      mergeProgressNote(saved)
      mutationErrorMessage = nil
      return nil
    } catch APIError.offline, APIError.server, APIError.cancelled {
      unresolvedNoteAction = "edit"
      unresolvedWriteState = .needsRefresh
      _ = await reconcileUnresolvedWrite()
      return mutationErrorMessage
    } catch {
      return error.userMessage(
        permission: "Your account does not have permission to edit this note.",
        fallback: "The note could not be saved. Try again.")
    }
  }

  func deleteProgressNote(_ note: ProgressNoteItem) async -> String? {
    guard !isMutating, unresolvedWriteState == nil,
      progressNotes.contains(where: { $0.id == note.id })
    else { return "This note is unavailable. Refresh and try again." }
    isMutating = true
    defer { isMutating = false }
    do {
      try await library.delete(collection: note.collection, id: note.recordID)
      progressNotes.removeAll { $0.id == note.id }
      if lastAddedProgressNoteID == note.recordID {
        lastAddedProgressNoteID = nil
      }
      mutationErrorMessage = nil
      return nil
    } catch APIError.offline, APIError.server, APIError.cancelled {
      unresolvedNoteAction = "delete"
      unresolvedWriteState = .needsRefresh
      _ = await reconcileUnresolvedWrite()
      return mutationErrorMessage
    } catch {
      return error.userMessage(
        permission: "Your account does not have permission to delete this note.",
        fallback: "The note could not be deleted. Try again.")
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
    editErrorMessage = nil
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
        offline: APIError.needsConnection("Adding a photo"),
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
    unresolvedNoteWriteIncludesPhoto = false
    unresolvedNoteCreate = false
    unresolvedNoteAction = nil
    unresolvedStatusWrite = false
    mutationErrorMessage = nil
  }

  private func reconcileUnresolvedWrite() async -> Bool {
    let didRefresh: Bool
    var refreshError: Error?
    do {
      try await library.refreshFromServer()
      didRefresh = await load()
    } catch {
      refreshError = error
      didRefresh = false
    }
    if didRefresh {
      unresolvedWriteState = .refreshed
      if let unresolvedNoteAction {
        mutationErrorMessage =
          "The \(unresolvedNoteAction) response was lost. Review the refreshed notes before changing them again."
        return true
      }
      if unresolvedStatusWrite {
        mutationErrorMessage =
          "The status response was lost. Review the refreshed status before changing it again."
        return true
      }
      switch item {
      case .diamond:
        mutationErrorMessage =
          unresolvedNoteWriteIncludesPhoto
          ? "The save response was lost. Review the refreshed progress notes and photos before adding another note."
          : "The save response was lost. Review the refreshed progress notes before adding another note."
      case .page:
        mutationErrorMessage = unresolvedNoteCreate
          ? "The save response was lost. Review the refreshed progress notes before adding another note."
          : "The upload response was lost. Review the refreshed photos before starting a new upload."
      case .book:
        mutationErrorMessage = "The save response was lost. Review the refreshed item."
      }
      return true
    }

    unresolvedWriteState = .needsRefresh
    let needsConnection = refreshError as? APIError == .offline
    if let unresolvedNoteAction {
      mutationErrorMessage =
        "The \(unresolvedNoteAction) result is unknown. Connect and refresh notes before changing them again."
      return false
    }
    if unresolvedStatusWrite {
      mutationErrorMessage =
        needsConnection
        ? "Changing the status needs a connection. Reconnect and refresh status before changing it again."
        : "Status is unknown because the item could not be refreshed. Refresh status before changing it again."
      return false
    }
    switch item {
    case .diamond:
      mutationErrorMessage =
        needsConnection
        ? "Adding a progress note needs a connection. Reconnect and refresh status before adding another note."
        : "Progress note status is unknown because the project could not be refreshed. Refresh status before adding another note."
    case .page:
      if unresolvedNoteCreate {
        mutationErrorMessage = needsConnection
          ? "Adding a progress note needs a connection. Reconnect and refresh status before adding another note."
          : "Progress note status is unknown. Connect and refresh before adding another note."
      } else {
        mutationErrorMessage = needsConnection
          ? "Adding a photo needs a connection. Reconnect and refresh status before starting another upload."
          : "Upload status is unknown because the photos could not be refreshed. Refresh status before starting another upload."
      }
    case .book:
      mutationErrorMessage = "Save status is unknown. Refresh the item before trying again."
    }
    return false
  }

  private func mergeProgressNote(_ saved: ProgressNoteItem) {
    progressNotes.removeAll { $0.id == saved.id }
    let insertionIndex =
      progressNotes.firstIndex {
        Self.progressNote(saved, precedes: $0)
      } ?? progressNotes.endIndex
    progressNotes.insert(saved, at: insertionIndex)
  }

  private static func progressNote(
    _ lhs: ProgressNoteItem,
    precedes rhs: ProgressNoteItem
  ) -> Bool {
    if lhs.date != rhs.date {
      return lhs.date > rhs.date
    }
    return lhs.created > rhs.created
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
