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
      let sessionStore = KeychainSessionStore()
      let client = PocketBaseClient(
        baseURL: configuration.pocketBaseURL,
        sessionStore: sessionStore
      )
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
