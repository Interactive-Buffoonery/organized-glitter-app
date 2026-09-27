import SwiftUI

@main
struct OrganizedGlitterApp: App {
  @State private var model: AppModel
  @State private var themeStore: ThemeStore
  #if DEBUG
    @AppStorage(OverviewFixtureProtocol.sampleDataKey) private var useSampleData = false
  #endif

  init() {
    UINavigationBar.applyCaveatLargeTitles()
    let themeStore = ThemeStore()
    _themeStore = State(initialValue: themeStore)
    _model = State(initialValue: Self.makeModel(themeStore: themeStore))
  }

  private static func makeModel(themeStore: ThemeStore) -> AppModel {
    do {
      let configuration = try AppConfiguration.load()
      let sessionStore: KeychainSessionStore
      let client: PocketBaseClient
      #if DEBUG
        URLProtocol.unregisterClass(OverviewFixtureProtocol.self)
        if OverviewFixtureProtocol.scenario != nil {
          URLProtocol.registerClass(OverviewFixtureProtocol.self)
          sessionStore = KeychainSessionStore(service: "OverviewFixtures")
          client = PocketBaseClient(
            baseURL: URL(string: "https://overview.example.invalid")!,
            sessionStore: sessionStore,
            urlSession: OverviewFixtureProtocol.session()
          )
        } else {
          sessionStore = KeychainSessionStore()
          client = PocketBaseClient(
            baseURL: configuration.pocketBaseURL, sessionStore: sessionStore)
        }
      #else
        sessionStore = KeychainSessionStore()
        client = PocketBaseClient(baseURL: configuration.pocketBaseURL, sessionStore: sessionStore)
      #endif
      let databaseURL = URL.applicationSupportDirectory
        .appending(path: "LocalLibrary", directoryHint: .isDirectory)
        .appending(path: "library.store")
      let localStore: LocalLibraryStore
      #if DEBUG
        localStore = try OverviewFixtureProtocol.scenario != nil
          ? LocalLibraryStore.inMemory() : LocalLibraryStore(databaseURL: databaseURL)
      #else
        localStore = try LocalLibraryStore(databaseURL: databaseURL)
      #endif
      return AppModel(
        client: client, sessionStore: sessionStore, themeStore: themeStore, localStore: localStore)
    } catch {
      return AppModel(configurationError: error, themeStore: themeStore)
    }
  }

  var body: some Scene {
    WindowGroup {
      ThemedRoot(flavor: themeStore.flavor) {
        RootView(model: model)
          #if DEBUG
            .onChange(of: useSampleData) {
              model = Self.makeModel(themeStore: themeStore)
            }
          #endif
      }
      .environment(themeStore)
    }
  }
}
