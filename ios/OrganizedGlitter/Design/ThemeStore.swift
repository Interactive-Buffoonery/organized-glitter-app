import Observation
import SwiftUI

/// Stores the last applied account theme and palette so signed-out and offline
/// screens keep the user's chosen appearance.
@MainActor
@Observable
final class ThemeStore {
  private static let storageKey = "selectedThemeFlavor"
  private static let paletteKey = "selectedThemePalette"

  private let defaults: UserDefaults

  var flavor: ThemeFlavor {
    didSet {
      defaults.set(flavor.rawValue, forKey: Self.storageKey)
    }
  }

  var palette: ThemePalette {
    didSet {
      defaults.set(palette.rawValue, forKey: Self.paletteKey)
    }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let stored = defaults.string(forKey: Self.storageKey)
    flavor = stored.flatMap(ThemeFlavor.init(rawValue:)) ?? .system
    palette = defaults.string(forKey: Self.paletteKey).flatMap(ThemePalette.init(rawValue:)) ?? .lilacDusk
  }
}

/// Resolves the active flavor against the system appearance and publishes both
/// the palette and the matching color scheme to the whole view tree.
struct ThemedRoot<Content: View>: View {
  @Environment(\.colorScheme) private var colorScheme

  let flavor: ThemeFlavor
  let palette: ThemePalette
  @ViewBuilder let content: Content

  var body: some View {
    let theme = flavor.theme(for: colorScheme, palette: palette)

    content
      .environment(\.theme, theme)
      .tint(theme.primary)
      .background(theme.themedBackground)
      .preferredColorScheme(flavor.preferredColorScheme)
  }
}
