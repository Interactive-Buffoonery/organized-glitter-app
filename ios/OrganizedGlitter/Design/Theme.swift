import SwiftUI

/// Semantic Berry Cream colors shared with the web app, expressed in sRGB.
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
  /// Optional elliptical bloom over the opaque page background.
  let backgroundBloom: Bloom?

  /// Secondary text directly over the page must remain readable across the glow.
  var pageSecondaryForeground: Color {
    backgroundBloom == nil ? mutedForeground : foreground
  }

  /// Quiet text actions directly over the page, readable across the glow.
  var pageAction: Color {
    backgroundBloom == nil ? Color(hex: 0xB82760) : Color(hex: 0xFFD6E6)
  }

  var backgroundGradient: LinearGradient {
    LinearGradient(colors: gradientStops, startPoint: .top, endPoint: .bottom)
  }

  /// The view to paint behind every screen. Light uses `backgroundGradient`;
  /// dark paints a flat `background` base with `backgroundBloom` over it so the
  /// "Berry Cream after dark" stage gets its bottom purple glow. Prefer
  /// this over `backgroundGradient` so dark mode picks up the bloom.
  var themedBackground: ThemeBackground {
    ThemeBackground(theme: self)
  }
}

extension Theme {
  /// Ellipse radii are fractions of the viewport width and height, matching
  /// the web theme independently of device size and orientation.
  struct Bloom: Equatable, Sendable {
    let center: UnitPoint
    let stops: [Stop]
    let radiusFraction: CGSize

    struct Stop: Equatable, Sendable {
      let color: Color
      let location: CGFloat
    }
  }
}

extension Theme {
  enum Radius {
    static let medium: CGFloat = 10
  }

  enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
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
