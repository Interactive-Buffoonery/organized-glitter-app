import SwiftUI
import UIKit

enum AppTab: Hashable {
  case home
  case library
  case craft(LibrarySection)
  case shelf(LibrarySection, status: String)
  case notes
  case search
}

struct AppShellView: View {
  let model: AppModel
  let client: PocketBaseClient
  let user: UserRecord
  let library: LibrarySession

  @AppStorage private var showCraftingStreak: Bool

  @Environment(\.scenePhase) private var scenePhase

  @Environment(\.horizontalSizeClass) private var sizeClass

  @State private var selectedTab: AppTab = .home
  @State private var notesLogEditor: LibraryItemDetailModel?
  @State private var homePath: [LibraryItem] = []
  @State private var homeLogEditor: LibraryItemDetailModel?
  @State private var homePendingLoggedItemID: LibraryItem.ID?
  @State private var homeRevealedLoggedItemID: LibraryItem.ID?
  @State private var homeRefreshGeneration = 0
  @State private var isShowingAccount = false
  @State private var libraryRefresh = LibraryRefresh()
  @State private var libraryRequest: LibraryRequest?
  @State private var accountPreferences: AccountPreferencesModel
  @State private var protectedFiles: ProtectedFileAccess
  @State private var connectivity = Connectivity()
  @State private var lastAnnouncedSyncMessage: String?
  @State private var formDrawer = FormDrawer()

  init(model: AppModel, client: PocketBaseClient, user: UserRecord, library: LibrarySession) {
    self.model = model
    self.client = client
    self.user = user
    self.library = library
    _showCraftingStreak = AppStorage(
      wrappedValue: false, CraftingStreak.preferenceKey(userID: user.id))
    _protectedFiles = State(initialValue: ProtectedFileAccess(client: client))
    _accountPreferences = State(
      initialValue: AccountPreferencesModel(
        client: client,
        user: user,
        onUserRefresh: model.replaceSignedInUser
      ))
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      Tab("Home", systemImage: "house", value: .home) {
        tabContent(NavigationStack(path: $homePath) {
          OverviewView(
            library: library, verticals: accountPreferences.verticals,
            logEditor: $homeLogEditor,
            loggedItemID: homeRevealedLoggedItemID,
            refreshGeneration: homeRefreshGeneration,
            onLibraryRequest: { request in
              libraryRequest = request
              selectedTab =
                request.section == .pages ? .search
                : sizeClass == .regular ? .shelf(request.section, status: request.status) : .library
            },
            onNotesRequest: { selectedTab = .notes },
            onSessionExpired: { await model.expireSession() }
          )
          .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
              Button("Account", systemImage: "person.crop.circle") {
                isShowingAccount = true
              }
              .accessibilityIdentifier("account.open")
              if showCraftingStreak {
                CraftingStreakButton(
                  library: library,
                  timeZone: accountPreferences.user.timezone.flatMap { TimeZone(identifier: $0) }
                    ?? .current,
                  onNotesRequest: { selectedTab = .notes })
              }
            }
            ToolbarItem(placement: .topBarTrailing) {
              CreateMenu(
                library: library,
                verticals: accountPreferences.verticals,
                onRefresh: { libraryRefresh.bump() },
                onSaved: { _ in libraryRefresh.bump() },
                onAddNote: presentNoteTargetPicker
              )
            }
          }
        }
        .progressNoteDrawer(editor: $homeLogEditor, onDismiss: {
          homeRevealedLoggedItemID = homePendingLoggedItemID
          homePendingLoggedItemID = nil
        }) { editor in
          if editor.lastAddedProgressNoteID != nil {
            homePendingLoggedItemID = editor.item.id
          } else {
            homeRefreshGeneration += 1
          }
        }
        .onChange(of: homeLogEditor == nil) { _, isDismissed in
          if !isDismissed { homeRevealedLoggedItemID = nil }
        })
      }

      // ponytail: iPad lists each craft and its shelves as sidebar rows so
      // Library never nests a second sidebar; compact width keeps one Library
      // tab with a craft picker. `defaultVisibility(_:for:)` doesn't hide tabs
      // on iPhone.
      if sizeClass == .regular {
        ForEach(LibrarySection.available(for: accountPreferences.verticals)) { section in
          craftSidebarSection(section)
        }
      } else {
        Tab("Library", systemImage: "rectangle.grid.2x2", value: .library) {
          tabContent(library(.browse))
        }
      }

      Tab("Notes", systemImage: "note.text", value: .notes) {
        tabContent(NavigationStack {
          NotesFeedView(
            library: library,
            verticals: accountPreferences.verticals,
            onAddNote: presentNoteTargetPicker
          )
          .navigationDestination(for: LibraryItem.self) { item in
            LibraryItemDetailDestination(
              item: item,
              library: library,
              logEditor: $notesLogEditor,
              onCollectionChanged: { libraryRefresh.bump() },
              onEditPageCount: { book in
                formDrawer.presentPageCountEditor(book: book, library: library)
              }
            )
          }
        }
        .progressNoteDrawer(editor: $notesLogEditor) { _ in libraryRefresh.bump() })
      }

      Tab("Search", systemImage: "magnifyingglass", value: .search) {
        tabContent(library(.search))
      }
    }
    .tabViewStyle(.sidebarAdaptable)
    .formDrawerHost(formDrawer)
    .onChange(of: sizeClass) { _, sizeClass in
      switch (sizeClass, selectedTab) {
      case (.regular, .library):
        if let first = LibrarySection.available(for: accountPreferences.verticals).first {
          selectedTab = .craft(first)
        }
      case (.compact, .craft), (.compact, .shelf):
        selectedTab = .library
      default:
        break
      }
    }
    .onChange(of: syncAnnouncement, initial: true) { _, announcement in
      guard let announcement else {
        lastAnnouncedSyncMessage = nil
        return
      }
      guard announcement != lastAnnouncedSyncMessage else { return }
      lastAnnouncedSyncMessage = announcement
      if UIAccessibility.isVoiceOverRunning {
        UIAccessibility.post(notification: .announcement, argument: announcement)
      }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { try? await library.refresh(force: true) } }
    }
    .onChange(of: library.generation) { _, _ in libraryRefresh.bump() }
    .environment(\.pocketBaseClient, client)
    .environment(\.protectedFiles, protectedFiles)
    .environment(\.connectionAvailable, connectivity.connectionAvailable)
    .task(id: user.id) { await protectedFiles.run() }
    .task { await accountPreferences.load() }
    .task { try? await library.refresh() }
    .task { await library.monitorConnectivity() }
    .task { await connectivity.monitor() }
    .sheet(isPresented: $isShowingAccount) {
      NavigationStack {
        AccountView(
          appModel: model, client: client, preferences: accountPreferences,
          showCraftingStreak: $showCraftingStreak)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { isShowingAccount = false }
            }
          }
      }
    }
  }

  private func presentNoteTargetPicker() {
    formDrawer.present(detents: [.medium, .large]) {
      NoteTargetPicker(
        library: library,
        verticals: accountPreferences.verticals,
        onSaved: { libraryRefresh.bump() })
    }
  }

  /// One sidebar section per craft: everything, then each shelf with its
  /// on-device count. Empty shelves are hidden unless selected, so emptying
  /// the open shelf doesn't pull the row out from under the user.
  private func craftSidebarSection(_ section: LibrarySection) -> some TabContent<AppTab> {
    let counts = library.shelfCounts(for: section)
    let shelves = section.shelfOrder.filter { status in
      counts[status, default: 0] > 0 || selectedTab == .shelf(section, status: status)
    }
    return TabSection(section.pickerTitle) {
      Tab(value: AppTab.craft(section)) {
        tabContent(library(.craft(section)))
      } label: {
        Label("All", systemImage: section.systemImage)
          .accessibilityLabel("All \(section.pickerTitle)")
      }
      .badge(counts.values.reduce(0, +))
      ForEach(shelves, id: \.self) { status in
        Tab(
          section.statusLabel(status), systemImage: section.statusSystemImage(status),
          value: AppTab.shelf(section, status: status)
        ) {
          tabContent(library(.shelf(section, status: status)))
        }
        .badge(counts[status, default: 0])
      }
    }
    .sectionActions {
      if let target = section.createTarget {
        Button("New \(target.title)", systemImage: "plus") { presentCreate(target) }
          .disabledWhileFormPresented(formDrawer)
      }
    }
  }

  private func presentCreate(_ target: CreateTarget) {
    formDrawer.present(detents: [.large]) {
      CreateEditor(
        target: target, library: library,
        onRefresh: { libraryRefresh.bump() },
        onSaved: { _ in libraryRefresh.bump() })
    }
  }

  private func library(_ presentation: LibraryPresentation) -> some View {
    LibraryView(
      library: library,
      presentation: presentation,
      libraryRefresh: libraryRefresh,
      verticals: accountPreferences.verticals,
      request: libraryRequest,
      onAddNote: presentNoteTargetPicker,
      onSessionExpired: { await model.expireSession() }
    )
  }

  private func tabContent<Content: View>(_ content: Content) -> some View {
    content
      .safeAreaPadding(.bottom, 24)
      .safeAreaInset(edge: .bottom) {
        LibrarySyncStatusView(library: library)
      }
  }

  private var syncAnnouncement: String? {
    if !library.conflicts.isEmpty { return "Some saved changes need your attention. Review." }
    if library.pendingCount > 0 { return "Saved on this device. Waiting to sync." }
    return library.syncMessage
  }
}
