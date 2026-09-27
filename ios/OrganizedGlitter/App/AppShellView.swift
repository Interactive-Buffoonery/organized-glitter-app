import SwiftUI
import UIKit

enum AppTab: Hashable {
  case home
  case library
  case craft(LibrarySection)
  case search
}

struct AppShellView: View {
  let model: AppModel
  let client: PocketBaseClient
  let user: UserRecord
  let library: LibrarySession

  @Environment(\.scenePhase) private var scenePhase

  @Environment(\.horizontalSizeClass) private var sizeClass

  @State private var selectedTab: AppTab = .home
  @State private var isShowingAccount = false
  @State private var libraryRefresh = LibraryRefresh()
  @State private var libraryRequest: LibraryRequest?
  @State private var accountPreferences: AccountPreferencesModel
  @State private var protectedFiles: ProtectedFileAccess
  @State private var connectivity = Connectivity()
  @State private var lastAnnouncedSyncMessage: String?

  init(model: AppModel, client: PocketBaseClient, user: UserRecord, library: LibrarySession) {
    self.model = model
    self.client = client
    self.user = user
    self.library = library
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
        tabContent(NavigationStack {
          OverviewView(
            library: library, verticals: accountPreferences.verticals,
            onLibraryRequest: { request in
              libraryRequest = request
              selectedTab = sizeClass == .regular ? .craft(request.section) : .library
            },
            onSessionExpired: { await model.expireSession() }
          )
          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              Button("Account", systemImage: "person.crop.circle") {
                isShowingAccount = true
              }
              .accessibilityIdentifier("account.open")
            }
            ToolbarItem(placement: .topBarTrailing) {
              CreateMenu(
                library: library,
                verticals: accountPreferences.verticals,
                onRefresh: { libraryRefresh.bump() },
                onSaved: { _ in libraryRefresh.bump() }
              )
            }
          }
        })
      }

      // ponytail: iPad lists crafts as sidebar rows so Library never nests a
      // second sidebar; compact width keeps one Library tab with a craft
      // picker. `defaultVisibility(_:for:)` doesn't hide tabs on iPhone.
      if sizeClass == .regular {
        TabSection("Library") {
          ForEach(LibrarySection.available(for: accountPreferences.verticals)) { section in
            Tab(section.pickerTitle, systemImage: section.systemImage, value: AppTab.craft(section)) {
              tabContent(library(.craft(section)))
            }
          }
        }
      } else {
        Tab("Library", systemImage: "rectangle.grid.2x2", value: .library) {
          tabContent(library(.browse))
        }
      }

      if LibraryPresentation.hasSearchTab {
        Tab("Search", systemImage: "magnifyingglass", value: .search) {
          tabContent(library(.search))
        }
      }
    }
    .tabViewStyle(.sidebarAdaptable)
    .onChange(of: sizeClass) { _, sizeClass in
      switch (sizeClass, selectedTab) {
      case (.regular, .library):
        if let first = LibrarySection.available(for: accountPreferences.verticals).first {
          selectedTab = .craft(first)
        }
      case (.compact, .craft):
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
        AccountView(appModel: model, client: client, preferences: accountPreferences)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { isShowingAccount = false }
            }
          }
      }
    }
  }

  private func library(_ presentation: LibraryPresentation) -> some View {
    LibraryView(
      library: library,
      presentation: presentation,
      libraryRefresh: libraryRefresh,
      verticals: accountPreferences.verticals,
      request: libraryRequest,
      onSessionExpired: { await model.expireSession() }
    )
  }

  private func tabContent<Content: View>(_ content: Content) -> some View {
    content.safeAreaInset(edge: .bottom) {
      LibrarySyncStatusView(library: library)
    }
  }

  private var syncAnnouncement: String? {
    if !library.conflicts.isEmpty { return "Some saved changes need your attention. Review." }
    if library.pendingCount > 0 { return "Saved on this device. Waiting to sync." }
    return library.syncMessage
  }
}
