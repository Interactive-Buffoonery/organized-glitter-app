import SwiftUI

struct LibraryView: View {
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.theme) private var theme
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @State private var model: LibraryModel
  @State private var path: [LibraryItem] = []
  @State private var editorTarget: LibraryEditorTarget?
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  let libraryRefresh: LibraryRefresh
  let verticals: VerticalPreferences
  let request: LibraryRequest?

  init(
    client: PocketBaseClient,
    userID: String,
    libraryRefresh: LibraryRefresh,
    verticals: VerticalPreferences = .defaultValue,
    request: LibraryRequest? = nil,
    onSessionExpired: @escaping @MainActor @Sendable () async -> Void = {}
  ) {
    let model = LibraryModel(client: client, userID: userID)
    model.onSessionExpired = onSessionExpired
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
    return ScrollView {
      LazyVStack(alignment: .leading, spacing: 12) {
        searchField

        if showsCraftPicker {
          craftPicker
        }

        filterControls
        libraryBody
        createAction
      }
      .frame(maxWidth: 760, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .padding(.bottom, 32)
      .frame(maxWidth: .infinity)
    }
    .refreshable { await model.load() }
    .navigationTitle("Library")
    .background {
      theme.themedBackground.ignoresSafeArea()
    }
    .overlay(alignment: .bottom) {
      if model.isLoading, model.hasLoaded {
        ProgressView("Loading more library items")
          .padding()
          .accessibilityAddTraits(.updatesFrequently)
      }
    }
    .onChange(of: model.isLoading) { _, isLoading in
      if isLoading, model.hasLoaded {
        AccessibilityNotification.Announcement("Loading more library items").post()
      }
    }
  }

  private var searchField: some View {
    @Bindable var model = model
    return HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(theme.pageSecondaryForeground)
        .accessibilityHidden(true)
      TextField(searchPrompt, text: $model.searchText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .accessibilityIdentifier("library.search")
        .accessibilityHint(searchHint)
        .onSubmit {
          Task { await model.load() }
        }
      if !model.searchText.isEmpty {
        Button {
          Task { await model.clearSearch() }
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(theme.pageSecondaryForeground)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear search")
        .accessibilityIdentifier("library.search.clear")
      }
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 44)
    .background(theme.card, in: .rect(cornerRadius: 12))
    .accessibilityElement(children: .contain)
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

  private var filterControls: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 4) {
          statusFilter(showsIcon: true)
          sortMenu(showsTitle: true)
        }
      } else {
        HStack(spacing: 8) {
          statusFilter(showsIcon: false)
          sortMenu(showsTitle: false)
        }
      }
    }
  }

  private func statusFilter(showsIcon: Bool) -> some View {
    Menu {
      Button {
        model.statusFilter = nil
      } label: {
        if model.statusFilter == nil {
          Label("All statuses", systemImage: "checkmark")
        } else {
          Text("All statuses")
        }
      }
      Divider()
      ForEach(model.section.statusOptions, id: \.self) { status in
        Button {
          model.statusFilter = status
        } label: {
          if model.statusFilter == status {
            Label(model.section.statusLabel(status), systemImage: "checkmark")
          } else {
            Text(model.section.statusLabel(status))
          }
        }
      }
    } label: {
      HStack(spacing: 5) {
        if showsIcon {
          Image(systemName: "line.3.horizontal.decrease.circle")
        }
        Text(model.statusFilter.map(model.section.statusLabel) ?? "All statuses")
        Image(systemName: "chevron.down")
          .font(.caption2.weight(.semibold))
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(minHeight: 44)
      .contentShape(.rect)
      .foregroundStyle(theme.foreground)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Filter by status")
    .accessibilityValue(model.statusFilter.map(model.section.statusLabel) ?? "All statuses")
    .accessibilityIdentifier("library.status")
  }

  private func sortMenu(showsTitle: Bool) -> some View {
    Menu {
      ForEach(model.section.sortOptions) { option in
        Button {
          model.sort = option
        } label: {
          if model.sort == option {
            Label(option.title, systemImage: "checkmark")
          } else {
            Text(option.title)
          }
        }
      }
    } label: {
      if showsTitle {
        Label(model.sort.title, systemImage: "arrow.up.arrow.down")
          .frame(maxWidth: .infinity, alignment: .leading)
          .frame(minHeight: 44)
          .contentShape(.rect)
          .foregroundStyle(theme.foreground)
      } else {
        Image(systemName: "arrow.up.arrow.down")
          .frame(width: 44, height: 44)
          .contentShape(.rect)
          .foregroundStyle(theme.foreground)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Sort library")
    .accessibilityValue(model.sort.title)
    .accessibilityIdentifier("library.sort")
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
          ContentUnavailableView(
            "Nothing here yet",
            systemImage: model.section.systemImage,
            description: Text("Items in this craft and filter will appear here.")
          )
          .frame(minHeight: 220)
        } else {
          ContentUnavailableView.search(text: model.searchText)
        }
      } else {
        LazyVGrid(columns: galleryColumns, alignment: .leading, spacing: 20) {
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
      LibraryGalleryCard(
        item: item,
        imageURL: item.artworkURL(
          using: model.client, thumb: ArtworkThumb.gallery, token: protectedFiles?.token))
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
    LibraryItemDetailDestination(
      item: item,
      client: model.client,
      userID: model.userID,
      onCollectionChanged: { await model.load() }
    )
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
    case .newBook:
      ColoringBookEditor(
        client: model.client,
        userID: model.userID,
        onLibraryRefresh: { await model.load() }
      ) { saved in
        Task { await selectSaved(.book(saved)) }
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

  private var searchPrompt: String {
    switch model.section {
    case .diamonds: "Search diamond art"
    case .books: "Search books"
    case .pages: "Search pages"
    }
  }

  private var searchHint: String {
    switch model.section {
    case .diamonds: "Search titles, artists, or companies"
    case .books: "Search titles, publishers, or illustrators"
    case .pages: "Search by book title or page number"
    }
  }
}

private enum LibraryEditorTarget: Identifiable {
  case newDiamond
  case newBook

  var id: String {
    switch self {
    case .newDiamond: "new-diamond"
    case .newBook: "new-book"
    }
  }
}
