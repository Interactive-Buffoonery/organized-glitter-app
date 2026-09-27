import SwiftUI

struct RootView: View {
  @Environment(\.theme) private var theme

  let model: AppModel

  var body: some View {
    Group {
      switch model.phase {
      case .restoring, .signedOut:
        WelcomeView(model: model)
      case .signedIn(let user):
        if let client = model.client, let library = model.library {
          AppShellView(model: model, client: client, user: user, library: library)
            .id(library.scope.storageKey)
        }
      case .offline:
        ConnectionUnavailableView(
          title: "You’re offline",
          message: "Reconnect to verify your session. Your saved sign-in has not been removed.",
          systemImage: "wifi.slash",
          retry: model.retrySessionRestoration
        )
      case .restorationFailed:
        ConnectionUnavailableView(
          title: "Couldn’t verify your session",
          message: "Your saved sign-in is still secure. Try again when the service is available.",
          systemImage: "arrow.clockwise",
          retry: model.retrySessionRestoration
        )
      case .configurationError(let message):
        ConfigurationErrorView(message: message)
      }
    }
    .background(theme.themedBackground.ignoresSafeArea())
    .animation(Theme.motion, value: model.phase)
  }
}

private struct ConnectionUnavailableView: View {
  @Environment(\.theme) private var theme

  let title: String
  let message: String
  let systemImage: String
  let retry: () -> Void

  var body: some View {
    AuthEntryContainer {
      VStack(spacing: 24) {
        BrandWordmark(size: 48, relativeTo: .title)
        ContentUnavailableView {
          Label(title, systemImage: systemImage)
        } description: {
          Text(message)
        } actions: {
          Button("Try Again", action: retry)
            .buttonStyle(AuthPrimaryButtonStyle())
            .frame(maxWidth: 280)
            .accessibilityIdentifier("sessionRetry")
        }
      }
      .foregroundStyle(theme.foreground)
    }
  }
}

private struct ConfigurationErrorView: View {
  @Environment(\.theme) private var theme

  let message: String

  var body: some View {
    AuthEntryContainer {
      VStack(spacing: 24) {
        BrandWordmark(size: 48, relativeTo: .title)
        ContentUnavailableView {
          Label("Configuration needed", systemImage: "wrench.and.screwdriver")
        } description: {
          Text(message)
        }
      }
      .foregroundStyle(theme.foreground)
    }
  }
}
