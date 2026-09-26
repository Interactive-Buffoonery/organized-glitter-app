import SwiftUI
import UIKit

extension Font {
  /// Caveat is the large-title face and the generated-cover title, never body
  /// text or controls (docs/design.md). `relativeTo` keeps Dynamic Type scaling.
  static func caveat(size: CGFloat, relativeTo textStyle: Font.TextStyle = .largeTitle) -> Font {
    .custom("Caveat", size: size, relativeTo: textStyle)
  }
}

extension UINavigationBar {
  /// Caveat large titles, once per screen. The legacy proxy attribute alone is
  /// lost after a pop, so every appearance carries it. Backgrounds keep the
  /// system defaults: transparent on iOS 26 (Liquid Glass and the scroll edge
  /// effect draw the bar) and at the scroll edge on iOS 18.
  static func applyCaveatLargeTitles() {
    guard let caveat = UIFont(name: "Caveat", size: 44) else { return }
    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: caveat),
      .foregroundColor: UIColor { traits in
        UIColor(traits.userInterfaceStyle == .dark ? Theme.dark.foreground : Theme.light.foreground)
      },
    ]
    let standard = UINavigationBarAppearance()
    let scrollEdge = UINavigationBarAppearance()
    scrollEdge.configureWithTransparentBackground()
    if #available(iOS 26, *) {
      standard.configureWithTransparentBackground()
    }
    standard.largeTitleTextAttributes = attributes
    scrollEdge.largeTitleTextAttributes = attributes
    appearance().standardAppearance = standard
    appearance().compactAppearance = standard
    appearance().scrollEdgeAppearance = scrollEdge
  }
}

/// Pastel circle + symbol, the Pagebound shelf-icon treatment. Decorative:
/// always pair with a visible text label.
struct IconBadge: View {
  @Environment(\.theme) private var theme

  let systemImage: String
  var surfaceIndex: Int = 0

  var body: some View {
    Image(systemName: systemImage)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(theme.surfaceForeground)
      .frame(width: 36, height: 36)
      .background(theme.accentSurface(surfaceIndex), in: .circle)
      .overlay {
        Circle().stroke(theme.stickerOutline, lineWidth: Theme.Sticker.outlineWidth)
      }
      .accessibilityHidden(true)
  }
}

/// Pastel sticker card: accent-surface fill, crisp outline, offset hard shadow.
/// Sets the foreground to the surface text color so nested text stays readable
/// in dark mode, where these fills stay light ("Glow Stickers").
struct StickerCard: ViewModifier {
  @Environment(\.theme) private var theme

  var surfaceIndex: Int = 0
  var cornerRadius: CGFloat = Theme.Radius.sticker

  func body(content: Content) -> some View {
    content
      .foregroundStyle(theme.surfaceForeground)
      .background(
        theme.accentSurface(surfaceIndex)
          .shadow(
            .drop(
              color: theme.stickerShadow,
              radius: 0,
              x: Theme.Sticker.shadowOffset.width,
              y: Theme.Sticker.shadowOffset.height
            )
          ),
        in: .rect(cornerRadius: cornerRadius)
      )
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius)
          .stroke(theme.stickerOutline, lineWidth: Theme.Sticker.outlineWidth)
      }
  }
}

/// The mint/peach capsule with the sticker treatment. Pressing collapses the
/// offset shadow and shifts the pill into it, so the sticker "pushes in".
struct PillButtonStyle: ButtonStyle {
  @Environment(\.theme) private var theme
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.subheadline.weight(.heavy))
      .foregroundStyle(theme.pillForeground)
      .padding(.vertical, 13)
      .frame(maxWidth: .infinity)
      .background(
        theme.pillFill
          .shadow(
            .drop(
              color: theme.stickerShadow,
              radius: 0,
              x: configuration.isPressed ? 0 : Theme.Sticker.shadowOffset.width,
              y: configuration.isPressed ? 0 : Theme.Sticker.shadowOffset.height
            )
          ),
        in: .capsule
      )
      .overlay {
        Capsule().stroke(theme.stickerOutline, lineWidth: Theme.Sticker.outlineWidth)
      }
      .offset(
        x: configuration.isPressed ? Theme.Sticker.shadowOffset.width : 0,
        y: configuration.isPressed ? Theme.Sticker.shadowOffset.height : 0
      )
      .opacity(isEnabled ? 1 : 0.5)
      .animation(reduceMotion ? nil : Theme.motion, value: configuration.isPressed)
  }
}

/// The page background. Light paints the blush-to-lilac `backgroundGradient`.
/// Dark paints a flat navy base with the theme's `backgroundBloom` over it —
/// the "Berry Cream after dark" stage. The opaque base keeps nested
/// backgrounds from doubling up the bloom.
struct ThemeBackground: View {
  let theme: Theme

  var body: some View {
    if let bloom = theme.backgroundBloom {
      GeometryReader { geo in
        RadialGradient(
          stops: bloom.stops.map { Gradient.Stop(color: $0.color, location: $0.location) },
          center: bloom.center,
          startRadius: 0,
          endRadius: max(geo.size.width, geo.size.height) * bloom.radiusFraction
        )
      }
      .background(theme.background)
    } else {
      theme.backgroundGradient
    }
  }
}

/// Replaces the stock grouped-list grey with the themed background surface.
struct ThemedScrollBackground: ViewModifier {
  @Environment(\.theme) private var theme

  func body(content: Content) -> some View {
    content
      .scrollContentBackground(.hidden)
      .background(theme.themedBackground)
  }
}

extension View {
  func stickerCard(_ surfaceIndex: Int = 0, cornerRadius: CGFloat = Theme.Radius.sticker) -> some View {
    modifier(StickerCard(surfaceIndex: surfaceIndex, cornerRadius: cornerRadius))
  }

  func themedScrollBackground() -> some View {
    modifier(ThemedScrollBackground())
  }
}

/// Icon plus written label; hue is never the only signal (docs/design.md).
struct StatusBadge: View {
  @Environment(\.theme) private var theme

  let label: String
  let systemImage: String

  var body: some View {
    Label(label, systemImage: systemImage)
      // ponytail: .titleAndIcon is load-bearing inside a List row, which otherwise
      // supplies .iconOnly and drops the written status VoiceOver depends on.
      .labelStyle(.titleAndIcon)
      .font(.caption.weight(.semibold))
      .foregroundStyle(theme.pageSecondaryForeground)
      .fixedSize(horizontal: false, vertical: true)
  }
}

struct AccessibleErrorLabel: View {
  @Environment(\.theme) private var theme

  let message: String

  var body: some View {
    Label(message, systemImage: "exclamationmark.triangle")
      .foregroundStyle(theme.foreground)
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
      .accessibilityLabel("Error: \(message)")
      .task(id: message) {
        AccessibilityNotification.Announcement("Error: \(message)").post()
      }
  }
}

/// A quiet native control without sticker chrome or movement on press.
struct QuietActionStyle: ButtonStyle {
  @Environment(\.theme) private var theme
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .labelStyle(.titleAndIcon)
      .font(.body.weight(.medium))
      .foregroundStyle(theme.foreground)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .frame(minHeight: 44)
      .background(
        configuration.isPressed ? theme.secondary : theme.card,
        in: .rect(cornerRadius: 12)
      )
      .opacity(isEnabled ? 1 : 0.5)
  }
}
