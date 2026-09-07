import Observation
import SwiftUI

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

  /// Sticker surface for the sidebar icon badge (docs/design.md).
  var surfaceIndex: Int {
    switch self {
    case .diamonds: 0
    case .books: 1
    case .pages: 2
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
}

@MainActor
@Observable
final class LibraryModel {
  let client: PocketBaseClient
  let userID: String

  var section = LibrarySection.diamonds
  var searchText = ""
  var statusFilter: String?
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

  func apply(_ request: LibraryRequest) {
    select(request.section)
    searchText = ""
    statusFilter = request.status
  }

  func select(_ section: LibrarySection) {
    guard self.section != section else {
      return
    }
    self.section = section
    statusFilter = nil
  }

  func load(reset: Bool = true) async {
    if !reset, isLoading || !canLoadMore {
      return
    }

    if reset {
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
      switch requestedSection {
      case .diamonds:
        let result: RecordList<DiamondProjectRecord> = try await client.list(
          collection: "projects",
          page: requestedPage,
          filter: filter(for: requestedSection),
          sort: "-updated",
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
          filter: filter(for: requestedSection),
          sort: "-updated",
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
          filter: filter(for: requestedSection),
          sort: "+page_number",
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

  private func filter(for section: LibrarySection) -> String {
    var filters = [
      PocketBaseFilter.equals(section == .pages ? .bookUser : .user, userID)
    ]

    let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !search.isEmpty {
      if section == .pages, let pageNumber = Int(search) {
        filters.append(PocketBaseFilter.equals(.pageNumber, pageNumber))
      } else {
        filters.append(
          PocketBaseFilter.contains(section == .pages ? .bookTitle : .title, search)
        )
      }
    }

    if let statusFilter {
      filters.append(PocketBaseFilter.equals(.status, statusFilter))
    }
    return PocketBaseFilter.all(filters)
  }

  private func applyPagination<Record>(_ result: RecordList<Record>) {
    currentPage = result.page
    totalPages = result.totalPages
  }
}

struct LibraryRequest: Equatable {
  let id = UUID()
  let section: LibrarySection
  let status: String
}

struct LibraryView: View {
  @Environment(\.theme) private var theme

  @State private var model: LibraryModel
  @State private var selection: LibraryItem?
  @State private var editorTarget: LibraryEditorTarget?
  @State private var deleteCandidate: LibraryItem?
  let libraryRefresh: LibraryRefresh
  let verticals: VerticalPreferences
  let request: LibraryRequest?

  init(
    client: PocketBaseClient,
    userID: String,
    libraryRefresh: LibraryRefresh,
    verticals: VerticalPreferences = .defaultValue,
    request: LibraryRequest? = nil
  ) {
    _model = State(initialValue: LibraryModel(client: client, userID: userID))
    self.libraryRefresh = libraryRefresh
    self.verticals = verticals
    self.request = request
  }

  var body: some View {
    @Bindable var model = model
    let sectionSelection = Binding<LibrarySection?>(
      get: { model.section },
      set: { newSection in
        if let newSection {
          model.select(newSection)
        }
      }
    )

    NavigationSplitView {
      List(LibrarySection.available(for: verticals), selection: sectionSelection) { section in
        HStack(spacing: 12) {
          IconBadge(systemImage: section.systemImage, surfaceIndex: section.surfaceIndex)
          Text(section.rawValue)
        }
        .tag(section)
        .listRowBackground(theme.card)
      }
      .themedScrollBackground()
      .navigationTitle("Library")
    } content: {
      Group {
        if let errorMessage = model.errorMessage, model.items.isEmpty {
          ContentUnavailableView {
            Label("Couldn’t load your library", systemImage: "exclamationmark.triangle")
          } description: {
            Text(errorMessage)
          } actions: {
            Button("Try Again") {
              Task { await model.load() }
            }
            .buttonStyle(PillButtonStyle())
            .frame(maxWidth: 240)
          }
        } else if model.isLoading, !model.hasLoaded {
          ProgressView("Loading \(model.section.rawValue.lowercased())")
        } else if model.items.isEmpty {
          ContentUnavailableView.search(text: model.searchText)
        } else {
          List(model.items, selection: $selection) { item in
            LibraryItemRow(item: item, imageURL: imageURL(for: item, bookThumb: "160x220"))
              .tag(item)
              .listRowBackground(theme.card)
              .task {
                if item == model.items.last {
                  await model.load(reset: false)
                }
              }
          }
          .themedScrollBackground()
          .refreshable {
            await model.load()
          }
          .overlay(alignment: .bottom) {
            if model.isLoading, model.hasLoaded {
              ProgressView()
                .padding()
            }
          }
        }
      }
      .navigationTitle(model.section.rawValue)
      .searchable(text: $model.searchText, prompt: searchPrompt)
      .onSubmit(of: .search) {
        Task { await model.load() }
      }
      .toolbar {
        ToolbarItemGroup {
          Menu {
            Button("All statuses") {
              model.statusFilter = nil
            }
            Divider()
            ForEach(model.section.statusOptions, id: \.self) { status in
              Button(status.organizedGlitterLabel) {
                model.statusFilter = status
              }
            }
          } label: {
            Label(
              model.statusFilter?.organizedGlitterLabel ?? "All statuses",
              systemImage: "line.3.horizontal.decrease.circle"
            )
          }
          .accessibilityLabel("Filter by status")

          if model.section == .diamonds {
            Button {
              editorTarget = .newDiamond
            } label: {
              Label("New project", systemImage: "plus")
            }
          } else if model.section == .books {
            Button {
              editorTarget = .newBook
            } label: {
              Label("New coloring book", systemImage: "plus")
            }
          }
        }
      }
    } detail: {
      if let selection {
        switch selection {
        case .diamond(let project):
          LibraryItemDetail(
            item: selection,
            onEdit: {
              editorTarget = .editDiamond(project)
            },
            onDelete: {
              deleteCandidate = selection
            }
          )
        case .book(let book):
          LibraryItemDetail(
            item: selection,
            imageURL: imageURL(for: selection, bookThumb: "320x420"),
            onEdit: {
              editorTarget = .editBook(book)
            },
            onDelete: {
              deleteCandidate = selection
            },
            deleteLabel: "Delete Coloring Book"
          )
        case .page(let page):
          LibraryItemDetail(
            item: selection,
            imageURL: imageURL(for: selection, bookThumb: "320x420"),
            onEdit: {
              editorTarget = .editPage(page)
            }
          )
        }
      } else {
        ContentUnavailableView(
          "Choose an item",
          systemImage: model.section.systemImage,
          description: Text("Select an item to see its details.")
        )
      }
    }
    .task(id: "\(model.section.rawValue)|\(model.statusFilter ?? "")|\(libraryRefresh.generation)") {
      selection = nil
      await model.load()
    }
    .onChange(of: request, initial: true) { _, request in
      guard let request else { return }
      selection = nil
      model.apply(request)
    }
    .onChange(of: verticals) { _, next in
      let available = LibrarySection.available(for: next)
      if !available.contains(model.section), let first = available.first {
        selection = nil
        model.select(first)
      }
    }
    .sheet(item: $editorTarget) { target in
      switch target {
      case .newDiamond:
        DiamondProjectEditor(
          client: model.client,
          userID: model.userID,
          onLibraryRefresh: { await model.load() }
        ) { saved in
          Task {
            await model.load()
            selection = model.items.first(where: { $0.id == "diamond:\(saved.id)" })
          }
        }
      case .editDiamond(let project):
        DiamondProjectEditor(
          client: model.client,
          userID: model.userID,
          project: project,
          onLibraryRefresh: { await model.load() }
        ) { saved in
          Task {
            await model.load()
            selection = model.items.first(where: { $0.id == "diamond:\(saved.id)" })
          }
        }
      case .newBook:
        ColoringBookEditor(
          client: model.client,
          userID: model.userID,
          onLibraryRefresh: { await model.load() }
        ) { saved in
          Task {
            await model.load()
            selection = model.items.first(where: { $0.id == "book:\(saved.id)" })
          }
        }
      case .editBook(let book):
        ColoringBookEditor(
          client: model.client,
          userID: model.userID,
          book: book,
          onLibraryRefresh: { await model.load() }
        ) { saved in
          Task {
            await model.load()
            selection = model.items.first(where: { $0.id == "book:\(saved.id)" })
          }
        }
      case .editPage(let page):
        ColoringPageEditor(
          client: model.client,
          page: page,
          onLibraryRefresh: { await model.load() }
        ) { saved in
          Task {
            await model.load()
            selection = model.items.first(where: { $0.id == "page:\(saved.id)" })
          }
        }
      }
    }
    .confirmationDialog(
      deleteConfirmationTitle,
      isPresented: Binding(
        get: { deleteCandidate != nil },
        set: { if !$0 { deleteCandidate = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button(deleteButtonLabel, role: .destructive) {
        guard let candidate = deleteCandidate else {
          return
        }
        deleteCandidate = nil
        selection = nil
        Task { await model.delete(candidate) }
      }
      Button("Cancel", role: .cancel) {
        deleteCandidate = nil
      }
    } message: {
      Text(deleteConfirmationMessage)
    }
    .alert(
      "Couldn’t delete item",
      isPresented: Binding(
        get: { model.mutationError != nil },
        set: { if !$0 { model.mutationError = nil } }
      )
    ) {
      Button("OK") {
        model.mutationError = nil
      }
    } message: {
      Text(model.mutationError ?? "")
    }
  }

  private var deleteConfirmationTitle: String {
    if case .book = deleteCandidate {
      "Delete this coloring book?"
    } else {
      "Delete this project?"
    }
  }

  private var deleteButtonLabel: String {
    if case .book = deleteCandidate {
      "Delete Coloring Book"
    } else {
      "Delete Project"
    }
  }

  private var deleteConfirmationMessage: String {
    if case .book = deleteCandidate {
      "This permanently removes the book and all of its page records after PocketBase confirms the request."
    } else {
      "This permanently removes the project after PocketBase confirms the request."
    }
  }

  private func imageURL(for item: LibraryItem, bookThumb: String) -> URL? {
    switch item {
    case .diamond:
      nil
    case .book(let book):
      book.coverImage?.nonEmpty.map {
        model.client.fileURL(
          collection: "coloring_books", recordID: book.id, filename: $0, thumb: bookThumb
        )
      }
    case .page(let page):
      page.photos.first.map {
        model.client.fileURL(
          collection: "coloring_pages", recordID: page.id, filename: $0, thumb: "160x160"
        )
      }
    }
  }

  private var searchPrompt: String {
    switch model.section {
    case .diamonds: "Search projects"
    case .books: "Search books"
    case .pages: "Book title or page number"
    }
  }
}

struct LibraryItemRow: View {
  @Environment(\.theme) private var theme

  let item: LibraryItem
  var imageURL: URL? = nil

  var body: some View {
    HStack(spacing: 12) {
      Group {
        if let imageURL {
          AsyncImage(url: imageURL) { image in
            image
              .resizable()
              .scaledToFill()
          } placeholder: {
            iconImage
          }
          .frame(width: thumbnailSize.width, height: thumbnailSize.height)
          .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
          iconImage
        }
      }
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(item.title)
          .font(.headline)
          .foregroundStyle(theme.cardForeground)
          .lineLimit(2)
        if !item.subtitle.isEmpty {
          Text(item.subtitle)
            .font(.subheadline)
            .foregroundStyle(theme.mutedForeground)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 8)
      StatusBadge(status: item.status)
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }

  private var iconImage: some View {
    IconBadge(systemImage: systemImage, surfaceIndex: iconSurfaceIndex)
  }

  private var iconSurfaceIndex: Int {
    switch item {
    case .diamond: 3
    case .book: 1
    case .page: 2
    }
  }

  private var thumbnailSize: CGSize {
    switch item {
    case .book: CGSize(width: 40, height: 55)
    default: CGSize(width: 44, height: 44)
    }
  }

  private var systemImage: String {
    switch item {
    case .diamond: "diamond"
    case .book: "book.closed"
    case .page: "doc.richtext"
    }
  }
}

struct LibraryItemDetail: View {
  @Environment(\.theme) private var theme

  let item: LibraryItem
  var imageURL: URL? = nil
  var onEdit: (() -> Void)?
  var onDelete: (() -> Void)?
  var deleteLabel: String = "Delete Project"

  var body: some View {
    List {
      Section {
        if let imageURL {
          AsyncImage(url: imageURL) { image in
            image
              .resizable()
              .scaledToFill()
          } placeholder: {
            RoundedRectangle(cornerRadius: Theme.Radius.medium)
              .fill(theme.muted)
              .overlay {
                Image(systemName: kindSystemImage)
                  .font(.title)
                  .foregroundStyle(theme.mutedForeground)
              }
          }
          .frame(width: detailImageSize.width, height: detailImageSize.height)
          .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
          .accessibilityLabel(imageAccessibilityLabel)
        }

        VStack(alignment: .leading, spacing: 12) {
          Text(item.title)
            .font(.largeTitle.bold())
          if !item.subtitle.isEmpty {
            Text(item.subtitle)
              .foregroundStyle(.secondary)
          }
          StatusBadge(status: item.status)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
      }
      .listRowBackground(theme.card)

      Group {
        switch item {
        case .diamond(let project):
          Section("Project") {
            LabeledContent("Kit", value: project.kitCategory.organizedGlitterLabel)
            LabeledContent(
              "Drill shape",
              value: project.drillShape?.nonEmpty?.organizedGlitterLabel ?? "Not set"
            )
            if let width = project.width, let height = project.height {
              LabeledContent("Size", value: "\(width.formatted()) × \(height.formatted()) cm")
            }
          }
        case .book(let book):
          Section("Progress") {
            LabeledContent("Completed", value: "\(book.completedPages ?? 0) of \(book.totalPages)")
            ProgressView(value: book.completionPercentage ?? 0, total: 100)
              .accessibilityLabel("Book completion")
          }
        case .page(let page):
          Section("Page") {
            LabeledContent("Page number", value: page.pageNumber.formatted())
            LabeledContent("Book", value: page.expand?.book?.title ?? "Unknown book")
          }
        }
      }
      .listRowBackground(theme.card)
    }
    .themedScrollBackground()
    .navigationTitle(item.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if let onEdit {
        ToolbarItem {
          Button("Edit", action: onEdit)
        }
      }
      if let onDelete {
        ToolbarItem {
          Menu {
            Button(deleteLabel, role: .destructive, action: onDelete)
          } label: {
            Label("More", systemImage: "ellipsis.circle")
          }
        }
      }
    }
  }

  private var kindSystemImage: String {
    switch item {
    case .diamond: "diamond"
    case .book: "book.closed"
    case .page: "doc.richtext"
    }
  }

  private var detailImageSize: CGSize {
    switch item {
    case .book: CGSize(width: 160, height: 220)
    default: CGSize(width: 160, height: 160)
    }
  }

  private var imageAccessibilityLabel: String {
    switch item {
    case .book: "Book cover"
    default: "Page photo"
    }
  }
}

private enum LibraryEditorTarget: Identifiable {
  case newDiamond
  case editDiamond(DiamondProjectRecord)
  case newBook
  case editBook(ColoringBookRecord)
  case editPage(ColoringPageRecord)

  var id: String {
    switch self {
    case .newDiamond: "new-diamond"
    case .editDiamond(let project): "diamond-\(project.id)"
    case .newBook: "new-book"
    case .editBook(let book): "book-\(book.id)"
    case .editPage(let page): "page-\(page.id)"
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
