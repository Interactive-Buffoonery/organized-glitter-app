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

  /// "Berry Cream after dark" — deep navy stage with a purple bloom rising
  /// from the bottom.
  static let dark = Theme(
    background: Color(hex: 0x05051A),
    foreground: Color(hex: 0xF7F2F7),
    card: Color(hex: 0x141028),
    cardForeground: Color(hex: 0xF7F2F7),
    popover: Color(hex: 0x0F0B28),
    popoverForeground: Color(hex: 0xF7F2F7),
    primary: Color(hex: 0xF58AB5),
    primaryForeground: Color(hex: 0x381423),
    secondary: Color(hex: 0x0F0B28),
    secondaryForeground: Color(hex: 0xF7F2F7),
    muted: Color(hex: 0x1C1636),
    mutedForeground: Color(hex: 0xBEB1C3),
    accent: Color(hex: 0xCAA4F9),
    accentForeground: Color(hex: 0x05051A),
    destructive: Color(hex: 0xEA3E3E),
    destructiveForeground: Color(hex: 0xF7F2F7),
    border: Color(hex: 0x37304B),
    ring: Color(hex: 0xF58AB5),
    gradientStops: [Color(hex: 0x05051A), Color(hex: 0x05051A)],
    backgroundBloom: Bloom(
      center: UnitPoint(x: 0.56, y: 1.0),
      stops: [
        Bloom.Stop(color: Color(hex: 0x5C27B5), location: 0.0),
        Bloom.Stop(color: Color(hex: 0x371475), location: 0.38),
        Bloom.Stop(color: .clear, location: 0.73),
      ],
      radiusFraction: 0.55
    )
  )
}

extension EnvironmentValues {
  @Entry var theme: Theme = .light
}
