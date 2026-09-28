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

  private func composited(_ color: Color, over background: Color) -> Color {
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var alpha: CGFloat = 0
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &alpha)
    let base = rgb(background)
    return Color(
      .sRGB,
      red: r * alpha + Double(base.r) / 255 * (1 - alpha),
      green: g * alpha + Double(base.g) / 255 * (1 - alpha),
      blue: b * alpha + Double(base.b) / 255 * (1 - alpha)
    )
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

  /// "Berry Cream after dark" paints a deep navy base with a bottom
  /// purple bloom; light retains its vertical gradient with no bloom.
  @Test
  func darkStageHasBloomLightDoesNot() {
    #expect(Theme.light.backgroundBloom == nil)
    #expect(Theme.dark.backgroundBloom != nil)
    #expect(rgb(Theme.dark.background) == (0x15, 0x15, 0x33))
  }

  @Test
  func secondaryTextMeetsMinimumContrast() {
    for stop in Theme.light.gradientStops {
      #expect(contrastRatio(Theme.light.mutedForeground, stop) >= 4.5)
    }
  }

  @Test
  func pageSecondaryTextRemainsReadableAcrossTheDarkGlow() throws {
    let bloom = try #require(Theme.dark.backgroundBloom)
    for stop in bloom.stops.dropLast() {
      let surface = composited(stop.color, over: Theme.dark.background)
      #expect(contrastRatio(Theme.dark.pageSecondaryForeground, surface) >= 4.5)
      #expect(contrastRatio(Theme.dark.mutedForeground, surface) >= 4.5)
    }
    #expect(contrastRatio(Theme.dark.pageSecondaryForeground, Theme.dark.background) >= 4.5)
  }

  @Test
  func errorTextMeetsMinimumContrastOnTheCard() {
    #expect(contrastRatio(Theme.light.foreground, Theme.light.card) >= 4.5)
    #expect(contrastRatio(Theme.dark.foreground, Theme.dark.card) >= 4.5)
    #expect(contrastRatio(Theme.dark.destructive, Theme.dark.card) >= 4.5)
    #expect(contrastRatio(Theme.dark.destructive, Theme.dark.background) >= 4.5)
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

  @Test
  func dismissingFormRunsItsCallbackOnceAndAllowsAnotherForm() {
    let drawer = FormDrawer()
    var dismissCount = 0
    drawer.present(detents: [.large], onDismiss: { dismissCount += 1 }) {
      Text("Progress draft")
    }
    drawer.dismiss()
    drawer.dismiss()
    #expect(dismissCount == 1)
    #expect(!drawer.isPresenting)

    drawer.present(detents: [.medium]) { Text("Next form") }
    #expect(drawer.isPresenting)
    #expect(drawer.route?.detents == [.medium])
  }

  @Test
  func openingAnotherFormPreservesTheActiveDraft() throws {
    let drawer = FormDrawer()
    var dismissCount = 0
    let accepted = drawer.present(detents: [.large], onDismiss: { dismissCount += 1 }) {
      Text("Draft in progress")
    }
    #expect(accepted)
    let activeID = try #require(drawer.route?.id)

    var builtRejectedContent = false
    var dismissedRejectedForm = false
    let rejected = drawer.present(
      detents: [.medium], onDismiss: { dismissedRejectedForm = true }
    ) {
      builtRejectedContent = true
      return Text("Another form")
    }

    #expect(!rejected)
    #expect(!builtRejectedContent)
    #expect(drawer.route?.id == activeID)
    #expect(drawer.route?.detents == [.large])
    drawer.dismiss()
    #expect(dismissCount == 1)
    #expect(!dismissedRejectedForm)
    #expect(drawer.present(detents: [.medium]) { Text("Next form") })
  }
}
