import SwiftUI

/// Semantic color tokens for the iOS app's own design system ("Berry Cream").
/// The web application keeps its Catppuccin themes; iOS ships one bright theme
/// with a light and a dark variant. Hex values, rules, and the approved
/// mockups are documented in `docs/design.md` and `docs/mockups/`.
struct Theme: Equatable, Sendable {
  let background: Color
  let foreground: Color
  let card: Color
  let cardForeground: Color
  let popover: Color
  let popoverForeground: Color
  let primary: Color
  let primaryForeground: Color
  let secondary: Color
  let secondaryForeground: Color
  let muted: Color
  let mutedForeground: Color
  let accent: Color
  let accentForeground: Color
  let destructive: Color
  let destructiveForeground: Color
  let border: Color
  let ring: Color

  /// Page background, top to bottom.
  let gradientStops: [Color]
  /// Pastel sticker-card fills, cycled by index: strawberry, lilac, mint,
  /// periwinkle, butter. Shared between light and dark ("Glow Stickers":
  /// dark mode keeps the light fills, so cards always carry dark text).
  let accentSurfaces: [Color]
  let surfaceForeground: Color
  let surfaceMutedForeground: Color
  let stickerOutline: Color
  let stickerShadow: Color
  let pillFill: Color
  let pillForeground: Color
  /// Optional radial bloom drawn over a flat `background` base. `nil` for the
  /// light variant, which uses `backgroundGradient`. The dark "Berry Cream
  /// after dark" stage paints a deep navy base with a berry-pink bloom rising
  /// from the bottom of the page.
  let backgroundBloom: Bloom?

  var backgroundGradient: LinearGradient {
    LinearGradient(colors: gradientStops, startPoint: .top, endPoint: .bottom)
  }

  /// The view to paint behind every screen. Light uses `backgroundGradient`;
  /// dark paints a flat `background` base with `backgroundBloom` over it so the
  /// "Berry Cream after dark" stage gets its bottom berry-pink glow. Prefer
  /// this over `backgroundGradient` so dark mode picks up the bloom.
  var themedBackground: ThemeBackground {
    ThemeBackground(theme: self)
  }

  func accentSurface(_ index: Int) -> Color {
    accentSurfaces[index % accentSurfaces.count]
  }
}

extension Theme {
  /// A radial color bloom drawn over the flat dark `background`. The web app's
  /// "Berry Cream after dark" stage paints an elliptical bloom from the bottom
  /// of the page; iOS approximates it with a circular radial gradient whose
  /// end radius scales with the longer screen dimension.
  struct Bloom: Equatable, Sendable {
    let center: UnitPoint
    let stops: [Stop]
    /// End radius as a fraction of `max(width, height)`.
    let radiusFraction: CGFloat

    struct Stop: Equatable, Sendable {
      let color: Color
      let location: CGFloat
    }
  }
}

extension Theme {
  enum Radius {
    static let medium: CGFloat = 10
    static let sticker: CGFloat = 20
  }

  enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
  }

  /// The offset hard shadow that makes sticker cards read as stickers.
  enum Sticker {
    static let shadowOffset = CGSize(width: 2.5, height: 3.5)
    static let outlineWidth: CGFloat = 1.5
  }

  /// Brief ease-out motion without bounce or elastic movement.
  static let motion = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)
}

extension Color {
  /// `0xRRGGBB`, matching the hex values in the approved HTML mockups.
  init(hex: UInt32, opacity: Double = 1) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: opacity
    )
  }
}
