import SwiftUI

@main
struct OrganizedGlitterApp: App {
  @State private var model: AppModel
  @State private var themeStore: ThemeStore

  init() {
    let themeStore = ThemeStore()
    _themeStore = State(initialValue: themeStore)

    do {
      let configuration = try AppConfiguration.load()
      let sessionStore: KeychainSessionStore
      let client: PocketBaseClient
      #if DEBUG
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
      _model = State(
        initialValue: AppModel(client: client, sessionStore: sessionStore, themeStore: themeStore)
      )
    } catch {
      _model = State(initialValue: AppModel(configurationError: error, themeStore: themeStore))
    }
  }

  var body: some Scene {
    WindowGroup {
      ThemedRoot(flavor: themeStore.flavor) {
        RootView(model: model)
      }
      .environment(themeStore)
    }
  }
}
