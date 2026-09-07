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
  private var listingEpoch = 0

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

  /// Observed by Library's load task. Section and status are included so craft
  /// and filter changes reload; `listingEpoch` changes when a Wishlist handoff
  /// clears search without changing either.
  var listingIdentity: String {
    "\(section.rawValue)|\(statusFilter ?? "")|\(listingEpoch)"
  }

  func apply(_ request: LibraryRequest) {
    select(request.section)
    searchText = ""
    statusFilter = request.status
    listingEpoch += 1
  }

  func select(_ section: LibrarySection) {
    guard self.section != section else {
      return
    }
    self.section = section
    statusFilter = nil
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
  func selection(afterSaving item: LibraryItem) async -> LibraryItem? {
    let snapshot = item.retainingListingContext(
      from: items.first(where: { $0.id == item.id }))
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

    let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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

struct LibraryRequest: Equatable {
  let id = UUID()
  let section: LibrarySection
  let status: String
}

struct LibraryView: View {
  @Environment(\.theme) private var theme
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @State private var model: LibraryModel
  @State private var path: [LibraryItem] = []
  @State private var editorTarget: LibraryEditorTarget?
  @State private var deleteCandidate: LibraryItem?
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
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
    let model = LibraryModel(client: client, userID: userID)
    if let request {
      model.apply(request)
    }
    model.align(to: verticals)
    _model = State(initialValue: model)
    self.libraryRefresh = libraryRefresh
    self.verticals = verticals
    self.request = request
  }

  var body: some View {
    Group {
      if sizeClass == .regular {
        padLibrary
      } else {
        phoneLibrary
      }
    }
    .task(id: "\(model.listingIdentity)|\(libraryRefresh.generation)") {
      path = []
      await model.load()
    }
    .onChange(of: request) { _, request in
      guard let request else { return }
      path = []
      model.apply(request)
    }
    .onChange(of: verticals) { _, next in
      let previous = model.listingIdentity
      model.align(to: next)
      if model.listingIdentity != previous {
        path = []
      }
    }
    .sheet(item: $editorTarget) { target in
      editor(for: target)
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
        path = []
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

  private var phoneLibrary: some View {
    NavigationStack(path: $path) {
      browsingScroll(showsCraftPicker: true)
        .navigationDestination(for: LibraryItem.self) { item in
          detail(for: item)
        }
    }
  }

  private var padLibrary: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      List(LibrarySection.available(for: verticals), selection: sectionSelection) { section in
        Label(section.pickerTitle, systemImage: section.systemImage)
          .tag(section)
      }
      .listStyle(.sidebar)
      .themedScrollBackground()
      .navigationTitle("Library")
    } detail: {
      NavigationStack(path: $path) {
        browsingScroll(showsCraftPicker: false)
          .navigationDestination(for: LibraryItem.self) { item in
            detail(for: item)
          }
      }
    }
    .navigationSplitViewStyle(.balanced)
  }

  private func browsingScroll(showsCraftPicker: Bool) -> some View {
    @Bindable var model = model
    return ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        PageHeader("Library")
        if showsCraftPicker {
          craftPicker
        }
        statusFilter
        libraryBody
        createAction
      }
      .frame(maxWidth: 760, alignment: .leading)
      .padding()
      .frame(maxWidth: .infinity)
    }
    .navigationTitle("Library")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .searchable(text: $model.searchText, prompt: searchPrompt)
    .onSubmit(of: .search) {
      Task { await model.load() }
    }
    .refreshable { await model.load() }
    .background {
      theme.themedBackground.ignoresSafeArea()
    }
    .overlay(alignment: .bottom) {
      if model.isLoading, model.hasLoaded {
        ProgressView()
          .padding()
      }
    }
  }

  private var craftPicker: some View {
    let selection = Binding<LibrarySection>(
      get: { model.section },
      set: { model.select($0) }
    )
    return Group {
      if dynamicTypeSize.isAccessibilitySize {
        Picker("Craft", selection: selection) {
          ForEach(LibrarySection.available(for: verticals)) { section in
            Text(section.pickerTitle).tag(section)
          }
        }
        .pickerStyle(.menu)
        .buttonStyle(QuietActionStyle())
      } else {
        Picker("Craft", selection: selection) {
          ForEach(LibrarySection.available(for: verticals)) { section in
            Text(section.pickerTitle).tag(section)
          }
        }
        .pickerStyle(.segmented)
      }
    }
    .accessibilityIdentifier("library.craft")
  }

  private var statusFilter: some View {
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
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(QuietActionStyle())
    .accessibilityLabel("Filter by status")
    .accessibilityValue(model.statusFilter?.organizedGlitterLabel ?? "All statuses")
  }

  @ViewBuilder
  private var libraryBody: some View {
    if let errorMessage = model.errorMessage, model.items.isEmpty {
      ContentUnavailableView {
        Label("Couldn’t load your library", systemImage: "exclamationmark.triangle")
      } description: {
        Text(errorMessage)
      } actions: {
        retryButton
      }
      .frame(minHeight: 280)
    } else if model.isLoading, !model.hasLoaded {
      ProgressView("Loading \(model.section.rawValue.lowercased())")
        .frame(maxWidth: .infinity, minHeight: 220)
    } else {
      if let errorMessage = model.errorMessage {
        AccessibleErrorLabel(message: errorMessage)
        retryButton
      }
      if model.items.isEmpty {
        if model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          EmptyFeatureView(
            title: "Nothing here yet",
            systemImage: model.section.systemImage,
            message: "Items in this craft and filter will appear here."
          )
          .frame(minHeight: 220)
        } else {
          ContentUnavailableView.search(text: model.searchText)
        }
      } else {
        LazyVGrid(columns: galleryColumns, alignment: .leading, spacing: 26) {
          ForEach(model.items) { item in
            galleryItem(item)
              .task {
                if item.id == model.items.last?.id {
                  await model.load(reset: false)
                }
              }
          }
        }
      }
    }
  }

  private var galleryColumns: [GridItem] {
    let item = GridItem(.flexible(), spacing: 18, alignment: .top)
    return dynamicTypeSize.isAccessibilitySize ? [item] : [item, item]
  }

  @ViewBuilder
  private func galleryItem(_ item: LibraryItem) -> some View {
    NavigationLink(value: item) {
      LibraryGalleryCard(item: item, imageURL: item.artworkURL(using: model.client))
    }
    .buttonStyle(.plain)
  }

  private var retryButton: some View {
    Button("Try Again") {
      Task { await model.load() }
    }
    .buttonStyle(QuietActionStyle())
    .disabled(model.isLoading)
  }

  @ViewBuilder
  private var createAction: some View {
    if let action = createDestination {
      Button {
        editorTarget = action.target
      } label: {
        Label(action.title, systemImage: "plus")
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(QuietActionStyle())
    }
  }

  private var createDestination: (title: String, target: LibraryEditorTarget)? {
    switch model.section {
    case .diamonds: ("Add diamond painting project", .newDiamond)
    case .books: ("Add coloring book", .newBook)
    case .pages: nil
    }
  }

  private var sectionSelection: Binding<LibrarySection?> {
    Binding(
      get: { model.section },
      set: { newSection in
        if let newSection {
          model.select(newSection)
        }
      }
    )
  }

  @ViewBuilder
  private func detail(for item: LibraryItem) -> some View {
    switch item {
    case .diamond(let project):
      LibraryItemDetail(
        item: item,
        imageURL: item.artworkURL(using: model.client),
        onEdit: { editorTarget = .editDiamond(project) },
        onDelete: { deleteCandidate = item }
      )
    case .book(let book):
      LibraryItemDetail(
        item: item,
        imageURL: item.artworkURL(using: model.client),
        onEdit: { editorTarget = .editBook(book) },
        onDelete: { deleteCandidate = item },
        deleteLabel: "Delete Coloring Book"
      )
    case .page(let page):
      LibraryItemDetail(
        item: item,
        imageURL: item.artworkURL(using: model.client),
        onEdit: { editorTarget = .editPage(page) }
      )
    }
  }

  @ViewBuilder
  private func editor(for target: LibraryEditorTarget) -> some View {
    switch target {
    case .newDiamond:
      DiamondProjectEditor(
        client: model.client,
        userID: model.userID,
        onLibraryRefresh: { await model.load() }
      ) { saved in
        Task { await selectSaved(.diamond(saved)) }
      }
    case .editDiamond(let project):
      DiamondProjectEditor(
        client: model.client,
        userID: model.userID,
        project: project,
        onLibraryRefresh: { await model.load() }
      ) { saved in
        Task { await selectSaved(.diamond(saved)) }
      }
    case .newBook:
      ColoringBookEditor(
        client: model.client,
        userID: model.userID,
        onLibraryRefresh: { await model.load() }
      ) { saved in
        Task { await selectSaved(.book(saved)) }
      }
    case .editBook(let book):
      ColoringBookEditor(
        client: model.client,
        userID: model.userID,
        book: book,
        onLibraryRefresh: { await model.load() }
      ) { saved in
        Task { await selectSaved(.book(saved)) }
      }
    case .editPage(let page):
      ColoringPageEditor(
        client: model.client,
        page: page,
        onLibraryRefresh: { await model.load() }
      ) { saved in
        Task { await selectSaved(.page(saved)) }
      }
    }
  }

  private func selectSaved(_ item: LibraryItem) async {
    if let selected = await model.selection(afterSaving: item) {
      path = [selected]
    } else {
      path = []
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

  private var searchPrompt: String {
    switch model.section {
    case .diamonds: "Search titles, artists, or companies"
    case .books: "Search titles, publishers, or illustrators"
    case .pages: "Book title or page number"
    }
  }
}

struct LibraryGalleryCard: View {
  @Environment(\.theme) private var theme

  let item: LibraryItem
  let imageURL: URL?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      RecordArtwork(url: imageURL, maxHeight: 230, emptyMinHeight: 170)
        .frame(maxWidth: .infinity, minHeight: 170, maxHeight: 230)
        .background(theme.card, in: .rect(cornerRadius: 10))
        .accessibilityHidden(true)

      Text(item.title)
        .font(.headline)
        .foregroundStyle(theme.foreground)
        .fixedSize(horizontal: false, vertical: true)

      if !item.libraryCaption.isEmpty {
        Text(item.libraryCaption)
          .font(.subheadline)
          .foregroundStyle(theme.pageSecondaryForeground)
          .fixedSize(horizontal: false, vertical: true)
      }

      StatusBadge(status: item.status, presentation: .quiet)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
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
          .accessibilityLabel(item.artworkAccessibilityLabel)
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
