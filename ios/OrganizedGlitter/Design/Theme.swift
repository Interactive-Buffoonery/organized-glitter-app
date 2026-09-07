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

  var backgroundGradient: LinearGradient {
    LinearGradient(colors: gradientStops, startPoint: .top, endPoint: .bottom)
  }

  func accentSurface(_ index: Int) -> Color {
    accentSurfaces[index % accentSurfaces.count]
  }
}

extension Theme {
  enum Radius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 10
    static let large: CGFloat = 12
    static let sticker: CGFloat = 20
  }

  enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
  }

  /// The offset hard shadow that makes sticker cards read as stickers.
  enum Sticker {
    static let shadowOffset = CGSize(width: 2.5, height: 3.5)
    static let outlineWidth: CGFloat = 1.5
  }

  /// ease-out-quart from DESIGN.json. No bounce, no elastic.
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
