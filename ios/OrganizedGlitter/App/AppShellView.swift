import SwiftUI

enum AppTab: Hashable {
  case overview
  case library
  case create
  case randomizer
  case account
}

struct AppShellView: View {
  let model: AppModel
  let client: PocketBaseClient
  let user: UserRecord

  @State private var selectedTab: AppTab = .overview
  @State private var libraryRefresh = LibraryRefresh()
  @State private var accountPreferences: AccountPreferencesModel

  init(model: AppModel, client: PocketBaseClient, user: UserRecord) {
    self.model = model
    self.client = client
    self.user = user
    _accountPreferences = State(
      initialValue: AccountPreferencesModel(
        client: client,
        user: user,
        onUserRefresh: model.replaceSignedInUser
      ))
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      Tab("Overview", systemImage: "house", value: .overview) {
        NavigationStack {
          OverviewView(client: client, userID: user.id)
        }
      }

      Tab("Library", systemImage: "square.grid.2x2", value: .library) {
        LibraryView(
          client: client,
          userID: user.id,
          libraryRefresh: libraryRefresh,
          verticals: accountPreferences.verticals
        )
      }

      Tab("Create", systemImage: "plus.circle.fill", value: .create) {
        NavigationStack {
          QuickCreateView(
            client: client,
            userID: user.id,
            libraryRefresh: libraryRefresh,
            verticals: accountPreferences.verticals
          )
        }
      }

      Tab("Randomizer", systemImage: "shuffle", value: .randomizer) {
        NavigationStack {
          RandomizerView()
        }
      }

      Tab("Account", systemImage: "person.crop.circle", value: .account) {
        NavigationStack {
          AccountView(
            appModel: model,
            client: client,
            preferences: accountPreferences
          )
        }
      }
    }
    .tabViewStyle(.sidebarAdaptable)
    .task { await accountPreferences.load() }
  }
}
