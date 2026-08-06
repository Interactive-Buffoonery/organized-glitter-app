import Observation
import SwiftUI

/// Stores the last applied account theme so signed-out and offline screens keep
/// the user's chosen appearance.
@MainActor
@Observable
final class ThemeStore {
  private static let storageKey = "selectedThemeFlavor"

  private let defaults: UserDefaults

  var flavor: ThemeFlavor {
    didSet {
      defaults.set(flavor.rawValue, forKey: Self.storageKey)
    }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let stored = defaults.string(forKey: Self.storageKey)
    flavor = stored.flatMap(ThemeFlavor.init(rawValue:)) ?? .system
  }
}

/// Resolves the active flavor against the system appearance and publishes both
/// the palette and the matching color scheme to the whole view tree.
struct ThemedRoot<Content: View>: View {
  @Environment(\.colorScheme) private var colorScheme

  let flavor: ThemeFlavor
  @ViewBuilder let content: Content

  var body: some View {
    let theme = flavor.theme(for: colorScheme)

    content
      .environment(\.theme, theme)
      .tint(theme.primary)
      .background(theme.backgroundGradient)
      .preferredColorScheme(flavor.preferredColorScheme)
  }
}
