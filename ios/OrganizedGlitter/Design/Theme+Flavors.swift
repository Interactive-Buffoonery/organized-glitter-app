import SwiftUI

/// One theme, two variants. Older builds (and the web app) stored Catppuccin
/// flavor names; those raw values no longer parse and fall back to `.system`.
enum ThemeFlavor: String, CaseIterable, Identifiable, Sendable {
  case system
  case light
  case dark

  var id: String { rawValue }

  var label: String {
    switch self {
    case .system: "System"
    case .light: "Light"
    case .dark: "Dark"
    }
  }

  /// `nil` lets the system decide; explicit variants pin their own appearance
  /// so the surrounding chrome matches the palette.
  var preferredColorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }

  func theme(for colorScheme: ColorScheme) -> Theme {
    switch self {
    case .system: colorScheme == .dark ? .dark : .light
    case .light: .light
    case .dark: .dark
    }
  }
}

extension Theme {
  /// "Berry Cream" — blush-to-lilac gradient, raspberry primary.
  static let light = Theme(
    background: Color(hex: 0xF8E9F6),
    foreground: Color(hex: 0x46323E),
    card: Color(hex: 0xFDF5F8),
    cardForeground: Color(hex: 0x46323E),
    popover: Color(hex: 0xFDF5F8),
    popoverForeground: Color(hex: 0x46323E),
    primary: Color(hex: 0xD23C77),
    primaryForeground: .white,
    secondary: Color(hex: 0xF6DCE6),
    secondaryForeground: Color(hex: 0x46323E),
    muted: Color(hex: 0xF3E4EC),
    mutedForeground: Color(hex: 0x765669),
    accent: Color(hex: 0x8535D4),
    accentForeground: .white,
    destructive: Color(hex: 0xC93A4C),
    destructiveForeground: .white,
    border: Color(hex: 0xE5CDD9),
    ring: Color(hex: 0xD23C77),
    gradientStops: [Color(hex: 0xFDEEF3), Color(hex: 0xF8E9F6), Color(hex: 0xE7DEFA)],
    backgroundBloom: nil
  )

  /// "Berry Cream after dark" — navy stage with a quiet lavender bloom rising
  /// from the bottom.
  static let dark = Theme(
    background: Color(hex: 0x151533),
    foreground: Color(hex: 0xF7F2F7),
    card: Color(hex: 0x231E3E),
    cardForeground: Color(hex: 0xF7F2F7),
    popover: Color(hex: 0x1D1938),
    popoverForeground: Color(hex: 0xF7F2F7),
    primary: Color(hex: 0xF58AB5),
    primaryForeground: Color(hex: 0x381423),
    secondary: Color(hex: 0x1D1938),
    secondaryForeground: Color(hex: 0xF7F2F7),
    muted: Color(hex: 0x2D2749),
    mutedForeground: Color(hex: 0xBEB1C3),
    accent: Color(hex: 0xCAA4F9),
    accentForeground: Color(hex: 0x151533),
    destructive: Color(hex: 0xF57E7E),
    destructiveForeground: Color(hex: 0xF7F2F7),
    border: Color(hex: 0x474059),
    ring: Color(hex: 0xF58AB5),
    gradientStops: [Color(hex: 0x151533), Color(hex: 0x151533)],
    backgroundBloom: Bloom(
      center: UnitPoint(x: 0.5, y: 1.18),
      stops: [
        Bloom.Stop(color: Color(hex: 0x8662A7, opacity: 0.45), location: 0.0),
        Bloom.Stop(color: Color(hex: 0x57406D, opacity: 0.22), location: 0.42),
        Bloom.Stop(color: .clear, location: 0.72),
      ],
      radiusFraction: CGSize(width: 1.2, height: 0.76)
    )
  )
}

extension EnvironmentValues {
  @Entry var theme: Theme = .light
}
