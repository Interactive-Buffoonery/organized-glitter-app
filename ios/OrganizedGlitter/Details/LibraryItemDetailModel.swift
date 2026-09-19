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

@MainActor
@Observable
final class LibraryItemDetailModel {
  let client: PocketBaseClient
  let userID: String

  private(set) var item: LibraryItem
  private(set) var progressNotes: [DiamondProgressNoteRecord] = []
  private(set) var bookPages: [ColoringPageRecord] = []
  private(set) var canLoadMoreBookPages = false
  private(set) var canLoadMoreProgressNotes = false

  var bookPageFilter = BookPageFilter.all
  var isLoading = false
  private(set) var hasLoaded = false
  var isLoadingMore = false
  var isMutating = false
  var errorMessage: String?
  var mutationErrorMessage: String?

  private var bookPagesPage = 0
  private var bookPagesTotalPages = 0
  private var progressNotesPage = 0
  private var progressNotesTotalPages = 0
  private var generation = 0

  init(item: LibraryItem, client: PocketBaseClient, userID: String) {
    self.item = item
    self.client = client
    self.userID = userID
  }

  func load() async {
    generation += 1
    let requestGeneration = generation
    isLoading = true
    errorMessage = nil
    defer {
      if requestGeneration == generation {
        isLoading = false
        hasLoaded = true
      }
    }

    do {
      switch item {
      case .diamond(let project):
        let loadedProject: DiamondProjectRecord = try await client.get(
          collection: "projects",
          id: project.id,
          expand: "company,artist"
        )
        let loadedNotes: RecordList<DiamondProgressNoteRecord> = try await client.list(
          collection: "progress_notes",
          page: 1,
          perPage: 20,
          filter: PocketBaseFilter.all([
            PocketBaseFilter.equals(.projectUser, userID),
            PocketBaseFilter.equals(.project, project.id),
          ]),
          sort: "-date,-created"
        )
        guard requestGeneration == generation else { return }
        item = .diamond(loadedProject)
        progressNotes = loadedNotes.items
        progressNotesPage = loadedNotes.page
        progressNotesTotalPages = loadedNotes.totalPages
        canLoadMoreProgressNotes = loadedNotes.page < loadedNotes.totalPages

      case .book(let book):
        let loadedBook: ColoringBookRecord = try await client.get(
          collection: "coloring_books",
          id: book.id,
          expand: "publisher,illustrator"
        )
        let loadedPages = try await bookPagesResult(bookID: book.id, page: 1)
        guard requestGeneration == generation else { return }
        item = .book(loadedBook)
        bookPages = loadedPages.items
        bookPagesPage = loadedPages.page
        bookPagesTotalPages = loadedPages.totalPages
        canLoadMoreBookPages = loadedPages.page < loadedPages.totalPages

      case .page(let page):
        let loaded: ColoringPageRecord = try await client.get(
          collection: "coloring_pages",
          id: page.id,
          expand: "book"
        )
        guard requestGeneration == generation else { return }
        item = .page(loaded)
      }
    } catch APIError.cancelled {
      return
    } catch {
      guard requestGeneration == generation else { return }
      errorMessage = error.detailLoadMessage
    }
  }

  func setBookPageFilter(_ filter: BookPageFilter) async {
    guard bookPageFilter != filter else { return }
    bookPageFilter = filter
    await reloadBookPages()
  }

  func reloadBookPages() async {
    guard case .book(let book) = item else { return }
    generation += 1
    let requestGeneration = generation
    isLoading = true
    errorMessage = nil
    defer {
      if requestGeneration == generation {
        isLoading = false
      }
    }

    do {
      let result = try await bookPagesResult(bookID: book.id, page: 1)
      guard requestGeneration == generation else { return }
      bookPages = result.items
      bookPagesPage = result.page
      bookPagesTotalPages = result.totalPages
      canLoadMoreBookPages = result.page < result.totalPages
    } catch APIError.cancelled {
      return
    } catch {
      guard requestGeneration == generation else { return }
      errorMessage = error.detailLoadMessage
    }
  }

  func loadMoreBookPages() async {
    guard case .book(let book) = item,
      !isLoadingMore,
      bookPagesPage < bookPagesTotalPages
    else {
      return
    }

    isLoadingMore = true
    errorMessage = nil
    defer { isLoadingMore = false }
    do {
      let result = try await bookPagesResult(bookID: book.id, page: bookPagesPage + 1)
      bookPages.append(contentsOf: result.items)
      bookPagesPage = result.page
      bookPagesTotalPages = result.totalPages
      canLoadMoreBookPages = result.page < result.totalPages
    } catch APIError.cancelled {
      return
    } catch {
      errorMessage = error.detailLoadMessage
    }
  }

  func loadMoreProgressNotes() async {
    guard case .diamond(let project) = item,
      !isLoadingMore,
      progressNotesPage < progressNotesTotalPages
    else {
      return
    }

    isLoadingMore = true
    errorMessage = nil
    defer { isLoadingMore = false }
    do {
      let result: RecordList<DiamondProgressNoteRecord> = try await client.list(
        collection: "progress_notes",
        page: progressNotesPage + 1,
        perPage: 20,
        filter: PocketBaseFilter.all([
          PocketBaseFilter.equals(.projectUser, userID),
          PocketBaseFilter.equals(.project, project.id),
        ]),
        sort: "-date,-created"
      )
      progressNotes.append(contentsOf: result.items)
      progressNotesPage = result.page
      progressNotesTotalPages = result.totalPages
      canLoadMoreProgressNotes = result.page < result.totalPages
    } catch APIError.cancelled {
      return
    } catch {
      errorMessage = error.detailLoadMessage
    }
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
    defer { isMutating = false }
    do {
      try await client.delete(collection: collection, id: recordID)
      return true
    } catch APIError.offline, APIError.server {
      do {
        let _: EmptyPocketBaseRecord = try await client.get(
          collection: collection,
          id: recordID
        )
        mutationErrorMessage =
          "Delete status is unknown. The item still appears on the server; check it before trying again."
        return false
      } catch APIError.notFound {
        return true
      } catch {
        mutationErrorMessage =
          "Delete status is unknown. Check the library before trying again."
        return false
      }
    } catch {
      mutationErrorMessage = error.userMessage(
        permission: "Your account does not have permission to delete this item.",
        fallback: "The item could not be deleted. Try again."
      )
      return false
    }
  }

  func addDiamondProgressNote(
    content: String,
    date: Date,
    photo: ProcessedDetailPhoto?
  ) async -> Bool {
    guard case .diamond(let project) = item, !isMutating else { return false }
    isMutating = true
    mutationErrorMessage = nil
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
      let _: DiamondProgressNoteRecord = try await client.create(
        collection: "progress_notes",
        multipart: form
      )
      await load()
      return true
    } catch APIError.offline, APIError.server {
      await load()
      mutationErrorMessage =
        "Upload status is unknown. The project was refreshed; check its photos before trying again."
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
    guard case .page(let page) = item, !isMutating else { return false }
    isMutating = true
    mutationErrorMessage = nil
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
      let saved: ColoringPageRecord = try await client.update(
        collection: "coloring_pages",
        id: page.id,
        multipart: form
      )
      item = .page(saved.withExpand(page.expand))
      await load()
      return true
    } catch APIError.offline, APIError.server {
      await load()
      mutationErrorMessage =
        "Upload status is unknown. The page was refreshed; check its photos before trying again."
      return false
    } catch {
      mutationErrorMessage = error.userMessage(
        permission: "Your account does not have permission to add a photo.",
        fallback: "The photo could not be added. Try again."
      )
      return false
    }
  }

  private func bookPagesResult(bookID: String, page: Int) async throws
    -> RecordList<ColoringPageRecord>
  {
    var filters = [
      PocketBaseFilter.equals(.book, bookID),
      PocketBaseFilter.equals(.bookUser, userID),
    ]
    if let status = bookPageFilter.status {
      filters.append(PocketBaseFilter.equals(.status, status))
    }
    return try await client.list(
      collection: "coloring_pages",
      page: page,
      perPage: 24,
      filter: PocketBaseFilter.all(filters),
      sort: "+page_number",
      expand: "book"
    )
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

private struct EmptyPocketBaseRecord: Decodable, Sendable {}

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
