import SwiftUI

struct RootView: View {
  @Environment(\.theme) private var theme

  let model: AppModel

  var body: some View {
    Group {
      switch model.phase {
      case .restoring:
        LaunchView()
      case .signedOut:
        NavigationStack {
          SignInView(model: model)
        }
      case .signedIn(let user):
        if let client = model.client {
          AppShellView(model: model, client: client, user: user)
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
    .background(theme.backgroundGradient)
  }
}

private struct LaunchView: View {
  var body: some View {
    VStack(spacing: 16) {
      Image("Logo")
        .resizable()
        .scaledToFit()
        .frame(width: 96, height: 96)
        .accessibilityHidden(true)
      ProgressView("Opening your library")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct ConnectionUnavailableView: View {
  let title: String
  let message: String
  let systemImage: String
  let retry: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label(title, systemImage: systemImage)
    } description: {
      Text(message)
    } actions: {
      Button("Try Again", action: retry)
        .buttonStyle(PillButtonStyle())
        .frame(maxWidth: 240)
    }
  }
}

private struct ConfigurationErrorView: View {
  let message: String

  var body: some View {
    ContentUnavailableView {
      Label("Configuration needed", systemImage: "wrench.and.screwdriver")
    } description: {
      Text(message)
    }
  }
}
