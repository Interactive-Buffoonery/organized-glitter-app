import SwiftUI

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

  @Environment(\.horizontalSizeClass) private var sizeClass

  @State private var selectedTab: AppTab = .home
  @State private var isShowingAccount = false
  @State private var libraryRefresh = LibraryRefresh()
  @State private var libraryRequest: LibraryRequest?
  @State private var accountPreferences: AccountPreferencesModel
  @State private var protectedFiles: ProtectedFileAccess

  init(model: AppModel, client: PocketBaseClient, user: UserRecord) {
    self.model = model
    self.client = client
    self.user = user
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
        NavigationStack {
          OverviewView(
            client: client, userID: user.id, verticals: accountPreferences.verticals,
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
                client: client,
                userID: user.id,
                verticals: accountPreferences.verticals,
                onRefresh: { libraryRefresh.bump() },
                onSaved: { _ in libraryRefresh.bump() }
              )
            }
          }
        }
      }

      // ponytail: iPad lists crafts as sidebar rows so Library never nests a
      // second sidebar; compact width keeps one Library tab with a craft
      // picker. `defaultVisibility(_:for:)` doesn't hide tabs on iPhone.
      if sizeClass == .regular {
        TabSection("Library") {
          ForEach(LibrarySection.available(for: accountPreferences.verticals)) { section in
            Tab(section.pickerTitle, systemImage: section.systemImage, value: AppTab.craft(section)) {
              library(.craft(section))
            }
          }
        }
      } else {
        Tab("Library", systemImage: "rectangle.grid.2x2", value: .library) {
          library(.browse)
        }
      }

      if LibraryPresentation.hasSearchTab {
        Tab(value: .search, role: .search) {
          library(.search)
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
    .environment(\.pocketBaseClient, client)
    .environment(\.protectedFiles, protectedFiles)
    .task(id: user.id) { await protectedFiles.run() }
    .task { await accountPreferences.load() }
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
      client: client,
      userID: user.id,
      presentation: presentation,
      libraryRefresh: libraryRefresh,
      verticals: accountPreferences.verticals,
      request: libraryRequest,
      onSessionExpired: { await model.expireSession() }
    )
  }
}
