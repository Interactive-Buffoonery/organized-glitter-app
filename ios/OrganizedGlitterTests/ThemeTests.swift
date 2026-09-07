import SwiftUI
import Testing
@testable import OrganizedGlitter

@MainActor
struct ThemeTests {
  /// Resolves a SwiftUI Color to 8-bit sRGB components so tokens can be
  /// compared against the hex values in the approved mockups.
  private func rgb(_ color: Color) -> (r: Int, g: Int, b: Int) {
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    return (Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
  }

  private func contrastRatio(_ first: Color, _ second: Color) -> Double {
    func luminance(_ color: Color) -> Double {
      let components = rgb(color)
      func channel(_ value: Int) -> Double {
        let normalized = Double(value) / 255
        return normalized <= 0.04045
          ? normalized / 12.92
          : pow((normalized + 0.055) / 1.055, 2.4)
      }
      return 0.2126 * channel(components.r)
        + 0.7152 * channel(components.g)
        + 0.0722 * channel(components.b)
    }

    let values = [luminance(first), luminance(second)].sorted()
    return (values[1] + 0.05) / (values[0] + 0.05)
  }

  @Test
  func hexInitializerRoundTrips() {
    #expect(rgb(Color(hex: 0xD23C77)) == (0xD2, 0x3C, 0x77))
    #expect(rgb(Color(hex: 0xFFFFFF)) == (255, 255, 255))
    #expect(rgb(Color(hex: 0x000000)) == (0, 0, 0))
  }

  /// The "Glow Stickers" contract: dark mode reuses the light pastel fills,
  /// so sticker text is always the dark surface foreground in both variants.
  @Test
  func stickerSurfacesAreSharedBetweenVariants() {
    #expect(Theme.light.accentSurfaces.count == 5)
    #expect(Theme.light.accentSurfaces == Theme.dark.accentSurfaces)
    #expect(Theme.light.surfaceForeground == Theme.dark.surfaceForeground)
  }

  /// "Berry Cream after dark" paints a deep navy base with a bottom
  /// berry-pink bloom; light stays flat with no bloom.
  @Test
  func darkStageHasBloomLightDoesNot() {
    #expect(Theme.light.backgroundBloom == nil)
    #expect(Theme.dark.backgroundBloom != nil)
    #expect(rgb(Theme.dark.background) == (0x05, 0x05, 0x1A))
  }

  @Test
  func secondaryTextMeetsMinimumContrast() {
    for surface in Theme.light.accentSurfaces {
      #expect(contrastRatio(Theme.light.surfaceMutedForeground, surface) >= 4.5)
    }
    for stop in Theme.light.gradientStops {
      #expect(contrastRatio(Theme.light.mutedForeground, stop) >= 4.5)
    }
  }

  @Test
  func accentSurfaceCyclesPastTheEnd() {
    #expect(Theme.light.accentSurface(5) == Theme.light.accentSurfaces[0])
    #expect(Theme.light.accentSurface(7) == Theme.light.accentSurfaces[2])
  }

  @Test
  func systemFlavorFollowsAppearance() {
    #expect(ThemeFlavor.system.theme(for: .light) == Theme.light)
    #expect(ThemeFlavor.system.theme(for: .dark) == Theme.dark)
    #expect(ThemeFlavor.system.preferredColorScheme == nil)
  }

  @Test
  func explicitFlavorsPinTheirOwnAppearance() {
    #expect(ThemeFlavor.light.preferredColorScheme == .light)
    #expect(ThemeFlavor.dark.preferredColorScheme == .dark)
  }

  @Test
  func storePersistsAndRestoresFlavor() throws {
    let suiteName = "ThemeTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(ThemeStore(defaults: defaults).flavor == .system)

    defaults.set(ThemeFlavor.dark.rawValue, forKey: "selectedThemeFlavor")
    #expect(ThemeStore(defaults: defaults).flavor == .dark)
  }

  /// Covers both genuinely unknown values and the retired Catppuccin flavor
  /// names older builds (and the web app) may have persisted.
  @Test
  func unknownOrRetiredStoredFlavorFallsBackToSystem() throws {
    let suiteName = "ThemeTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set("catppuccin-mocha", forKey: "selectedThemeFlavor")
    #expect(ThemeStore(defaults: defaults).flavor == .system)
  }
}
