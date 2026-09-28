import SwiftUI

struct LibraryView: View {
  @Environment(FormDrawer.self) private var formDrawer
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.theme) private var theme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @State private var model: LibraryModel
  @State private var path: [LibraryItem] = []
  @State private var logEditor: LibraryItemDetailModel?
  let presentation: LibraryPresentation
  let libraryRefresh: LibraryRefresh
  let verticals: VerticalPreferences
  let request: LibraryRequest?
  let onAddNote: () -> Void

  init(
    library: LibrarySession,
    presentation: LibraryPresentation = .browse,
    libraryRefresh: LibraryRefresh,
    verticals: VerticalPreferences = .defaultValue,
    request: LibraryRequest? = nil,
    onAddNote: @escaping () -> Void,
    onSessionExpired: @escaping @MainActor @Sendable () async -> Void = {}
  ) {
    let model = LibraryModel(library: library)
    model.onSessionExpired = onSessionExpired
    if let section = presentation.pinnedSection {
      model.select(section)
      if case .shelf(_, let status) = presentation { model.statusFilter = status }
    } else {
      model.align(to: verticals)
    }
    if let request, presentation.accepts(request) {
      model.apply(request)
    }
    _model = State(initialValue: model)
    self.presentation = presentation
    self.libraryRefresh = libraryRefresh
    self.verticals = verticals
    self.request = request
    self.onAddNote = onAddNote
  }

  var body: some View {
    NavigationStack(path: $path) {
      browsingScroll
        .navigationDestination(for: LibraryItem.self) { item in
          detail(for: item)
        }
    }
    .progressNoteDrawer(editor: $logEditor) { _ in await model.load() }
    .task(id: model.listingIdentity) {
      path = []
      guard !isAwaitingSearch else { return }
      await model.load()
    }
    .onChange(of: libraryRefresh.generation) { _, _ in
      Task { await model.load() }
    }
    .onChange(of: request) { _, request in
      guard let request, presentation.accepts(request) else { return }
      path = []
      model.apply(request)
    }
    .onChange(of: verticals) { _, next in
      guard presentation.pinnedSection != nil else {
        let previous = model.listingIdentity
        model.align(to: next)
        if model.listingIdentity != previous {
          path = []
        }
        return
      }
    }
  }

  /// A craft with nothing in it gets one prompt instead of an empty grid.
  private var isEmptyLibrary: Bool {
    presentation != .search && model.library.hasSnapshot && model.hasLoaded
      && !model.isLoading && model.items.isEmpty
      && model.errorMessage == nil && model.statusFilter == nil
      && model.committedSearch.isEmpty
  }

  /// The search tab shows a prompt until something has been searched.
  private var isAwaitingSearch: Bool {
    presentation == .search && model.committedSearch.isEmpty
  }

  @ViewBuilder
  private var browsingScroll: some View {
    let scroll = ScrollView {
      LazyVStack(alignment: .leading, spacing: 12) {
        if presentation.showsCraftPicker {
          craftPicker
        }

        if presentation.showsStatusChips, !isEmptyLibrary {
          statusChips
        }
        libraryBody
      }
      .frame(maxWidth: 760, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .padding(.bottom, 32)
      .frame(maxWidth: .infinity)
    }
    .refreshable { await model.refresh() }
    .navigationTitle(presentation.title)
    .background {
      theme.themedBackground.ignoresSafeArea()
    }
    .toolbar {
      if presentation != .search {
        if !isEmptyLibrary {
          ToolbarItem(placement: .topBarTrailing) { sortMenu }
        }
        ToolbarItem(placement: .topBarTrailing) {
          CreateMenu(
            library: model.library,
            verticals: verticals,
            onRefresh: { await model.load() },
            onSaved: created,
            onAddNote: onAddNote
          )
        }
      }
    }
    .overlay(alignment: .bottom) {
      if model.isLoading, !model.items.isEmpty {
        ProgressView("Loading more library items")
          .padding()
          .accessibilityAddTraits(.updatesFrequently)
      }
    }
    .onChange(of: model.isLoading) { _, isLoading in
      if isLoading, !model.items.isEmpty {
        AccessibilityNotification.Announcement("Loading more library items").post()
      }
    }

    if presentation.isSearchable {
      scroll
        .searchable(text: Bindable(model).searchText, prompt: searchPrompt)
        .onSubmit(of: .search) {
          Task { await model.load() }
        }
        .onChange(of: model.searchText) { _, text in
          if text.isEmpty {
            Task { await model.clearSearch() }
          }
        }
    } else {
      scroll
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

  private var statusChips: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          statusChip(nil, title: "All")
          ForEach(model.section.statusOptions, id: \.self) { status in
            statusChip(status, title: model.section.statusLabel(status))
          }
        }
        .padding(.horizontal, 20)
      }
      .scrollIndicators(.hidden)
      .onAppear { proxy.scrollTo(model.statusFilter ?? "", anchor: .center) }
      .onChange(of: model.statusFilter) { _, status in
        withAnimation(Theme.motion) { proxy.scrollTo(status ?? "", anchor: .center) }
      }
    }
    .padding(.horizontal, -20)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Filter by status")
  }

  @ViewBuilder
  private func statusChip(_ status: String?, title: String) -> some View {
    let isSelected = model.statusFilter == status
    let chip = Button(title) { model.statusFilter = status }
      .buttonBorderShape(.capsule)
      .accessibilityAddTraits(isSelected ? .isSelected : [])
      .accessibilityIdentifier("library.status.\(status ?? "all")")
      .id(status ?? "")
    if isSelected {
      chip.buttonStyle(.borderedProminent).foregroundStyle(theme.primaryForeground)
    } else {
      chip.buttonStyle(.bordered).foregroundStyle(theme.foreground)
    }
  }

  private var sortMenu: some View {
    Menu {
      Picker("Sort", selection: Bindable(model).sort) {
        ForEach(model.section.sortOptions) { option in
          Text(option.title).tag(option)
        }
      }
    } label: {
      Label("Sort", systemImage: "arrow.up.arrow.down")
    }
    .accessibilityValue(model.sort.title)
    .accessibilityIdentifier("library.sort")
  }

  @ViewBuilder
  private var libraryBody: some View {
    if !model.library.hasSnapshot, model.library.syncMessage == nil,
      model.errorMessage == nil
    {
      ProgressView("Loading \(model.section.rawValue.lowercased())")
        .frame(maxWidth: .infinity, minHeight: 220)
    } else if !model.library.hasSnapshot || (model.errorMessage != nil && model.items.isEmpty) {
      ContentUnavailableView {
        Label("Couldn’t load your library", systemImage: "exclamationmark.triangle")
      } description: {
        Text(model.errorMessage ?? model.library.syncMessage ?? "Connect to download your library.")
      } actions: {
        retryButton
      }
      .frame(minHeight: 280)
    } else if isAwaitingSearch {
      ContentUnavailableView(
        "Search your library",
        systemImage: "magnifyingglass",
        description: Text("Find projects, books, and pages by title, artist, or company.")
      )
      .frame(minHeight: 280)
    } else if model.items.isEmpty, model.isLoading || !model.hasLoaded {
      ProgressView("Loading \(model.section.rawValue.lowercased())")
        .frame(maxWidth: .infinity, minHeight: 220)
    } else {
      if let errorMessage = model.errorMessage {
        AccessibleErrorLabel(message: errorMessage)
        retryButton
      }
      if model.items.isEmpty {
        emptyState
          .frame(minHeight: 280)
      } else if model.isShelved {
        LazyVGrid(columns: galleryColumns, alignment: .leading, spacing: 20) {
          ForEach(model.shelves) { shelf in
            Section {
              ForEach(shelf.items) { item in
                galleryItem(item)
              }
            } header: {
              shelfHeader(shelf)
            }
          }
        }
      } else {
        LazyVGrid(columns: galleryColumns, alignment: .leading, spacing: 20) {
          ForEach(model.items) { item in
            galleryItem(item)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var emptyState: some View {
    if !model.committedSearch.isEmpty {
      ContentUnavailableView.search(text: model.committedSearch)
    } else if let status = model.statusFilter {
      ContentUnavailableView {
        Label("Nothing \(model.section.statusLabel(status).lowercased())", systemImage: "line.3.horizontal.decrease.circle")
      } description: {
        Text("Try another status.")
      } actions: {
        Button("Show All") { model.statusFilter = nil }
          .buttonStyle(QuietActionStyle())
      }
    } else {
      switch model.section {
      case .diamonds:
        firstItemPrompt("Add your first kit", message: "Diamond painting projects you add appear here as covers.", target: .diamond)
      case .books:
        firstItemPrompt("Add your first book", message: "Coloring books you add appear here as covers.", target: .book)
      case .pages:
        ContentUnavailableView(
          "No pages yet",
          systemImage: model.section.systemImage,
          description: Text("Pages come from your coloring books.")
        )
      }
    }
  }

  private func firstItemPrompt(_ title: String, message: String, target: CreateTarget) -> some View {
    ContentUnavailableView {
      Label(title, systemImage: model.section.systemImage)
    } description: {
      Text(message)
    } actions: {
      Button(title) {
        formDrawer.present(detents: [.large]) {
          CreateEditor(
            target: target, library: model.library,
            onRefresh: { await model.load() }, onSaved: created)
        }
      }
      .buttonStyle(.borderedProminent)
      .foregroundStyle(theme.primaryForeground)
      .disabledWhileFormPresented(formDrawer)
      .accessibilityIdentifier("library.first")
    }
  }

  private func created(_ item: LibraryItem) {
    if item.section == model.section {
      Task { await selectSaved(item) }
    } else {
      libraryRefresh.bump()
    }
  }

  private var galleryColumns: [GridItem] {
    let item = GridItem(.flexible(), spacing: 18, alignment: .top)
    return dynamicTypeSize.isAccessibilitySize ? [item] : [item, item]
  }

  private func galleryItem(_ item: LibraryItem) -> some View {
    NavigationLink(value: item) {
      LibraryGalleryCard(
        item: item,
        imageURL: protectedFiles?.artworkURL(for: item, thumb: ArtworkThumb.gallery),
        showsStatus: !model.committedSearch.isEmpty)
    }
    .buttonStyle(.plain)
    .task {
      if item.id == model.items.last?.id {
        await model.load(reset: false)
      }
    }
  }

  /// Matches Home's section headers; tapping narrows Library to the shelf.
  private func shelfHeader(_ shelf: LibraryShelf) -> some View {
    let title = model.section.statusLabel(shelf.status)
    let count = model.shelfCounts[shelf.status] ?? shelf.items.count
    return Button {
      model.statusFilter = shelf.status
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(title)
          .font(.title3.weight(.semibold))
          .foregroundStyle(theme.foreground)
        Text(count, format: .number)
          .font(.subheadline.weight(.medium))
          .monospacedDigit()
          .foregroundStyle(theme.pageSecondaryForeground)
        Image(systemName: "chevron.right")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(theme.primary)
      }
      .padding(.top, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(title), \(count)")
    .accessibilityHint("Shows only this shelf")
    .accessibilityAddTraits([.isHeader, .isButton])
    .accessibilityIdentifier("library.shelf.\(shelf.status)")
  }

  private var retryButton: some View {
    Button("Try Again") {
      Task { await model.refresh() }
    }
    .buttonStyle(QuietActionStyle())
    .disabled(model.isLoading || model.library.isSyncing)
    .accessibilityIdentifier("library.retry")
  }

  @ViewBuilder
  private func detail(for item: LibraryItem) -> some View {
    LibraryItemDetailDestination(
      item: item,
      library: model.library,
      logEditor: $logEditor,
      onCollectionChanged: { await model.load() },
      onEditPageCount: { book in
        formDrawer.presentPageCountEditor(book: book, library: model.library) { saved in
          model.acceptSavedBook(saved)
        }
      }
    )
    .environment(formDrawer)
  }

  private func selectSaved(_ item: LibraryItem) async {
    if let selected = await model.selection(afterSaving: item, previousSelection: path.last) {
      path = [selected]
    } else {
      path = []
    }
  }

  private var searchPrompt: String {
    switch model.section {
    case .diamonds: "Search diamond art"
    case .books: "Search books"
    case .pages: "Search pages"
    }
  }
}
