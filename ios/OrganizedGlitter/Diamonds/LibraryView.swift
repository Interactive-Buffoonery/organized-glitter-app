import SwiftUI

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
    if let selected = await model.selection(afterSaving: item, previousSelection: path.last) {
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
