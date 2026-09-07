import SwiftUI

extension Font {
  /// Caveat is the personal-library signature: the page H1 and section headers,
  /// never body text or controls (docs/design.md). `relativeTo` keeps Dynamic
  /// Type scaling.
  static func caveat(size: CGFloat, relativeTo textStyle: Font.TextStyle = .largeTitle) -> Font {
    .custom("Caveat", size: size, relativeTo: textStyle)
  }
}

/// Caveat section header, one size below `PageHeader`.
struct SectionHeader: View {
  @Environment(\.theme) private var theme

  let title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    Text(title)
      .font(.caveat(size: 28, relativeTo: .title2))
      .foregroundStyle(theme.foreground)
      .accessibilityAddTraits(.isHeader)
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
      .animation(Theme.motion, value: configuration.isPressed)
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

struct PageHeader: View {
  @Environment(\.theme) private var theme

  let title: String
  let subtitle: String?

  init(_ title: String, subtitle: String? = nil) {
    self.title = title
    self.subtitle = subtitle
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
      Text(title)
        .font(.caveat(size: 40))
        .foregroundStyle(theme.foreground)
      if let subtitle {
        Text(subtitle)
          .font(.body)
          .foregroundStyle(theme.mutedForeground)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}

struct EmptyFeatureView: View {
  let title: String
  let systemImage: String
  let message: String

  var body: some View {
    ContentUnavailableView {
      Label(title, systemImage: systemImage)
    } description: {
      Text(message)
    }
  }
}

struct AccessibleErrorLabel: View {
  @Environment(\.theme) private var theme

  let message: String

  var body: some View {
    Label(message, systemImage: "exclamationmark.triangle")
      .foregroundStyle(theme.destructive)
      .accessibilityLabel("Error: \(message)")
      .task(id: message) {
        AccessibilityNotification.Announcement("Error: \(message)").post()
      }
  }
}

struct StatusBadge: View {
  @Environment(\.theme) private var theme

  let status: String
  /// On pastel sticker fills the theme tints lose contrast in dark mode (light
  /// tint on light fill), so surface placement flattens to the surface text
  /// color. Status stays distinguishable through its icon and written label.
  var onSurface = false

  var body: some View {
    Label(status.organizedGlitterLabel, systemImage: systemImage)
      // ponytail: both modifiers are load-bearing inside a List row. A bare Label
      // inherits the ambient style, and List rows supply .iconOnly, which drops the
      // written status text the accessibility contract below depends on. Fixing only
      // the horizontal axis keeps the capsule at its natural height instead of
      // stretching to fill the row.
      .labelStyle(.titleAndIcon)
      .font(.caption.weight(.semibold))
      .foregroundStyle(tint)
      .padding(.horizontal, 9)
      .padding(.vertical, 6)
      .background(tint.opacity(0.12), in: .capsule)
      .fixedSize(horizontal: true, vertical: false)
  }

  private var systemImage: String {
    switch status {
    case "completed": "checkmark.circle.fill"
    case "progress", "in_progress": "play.circle.fill"
    case "onhold", "on_hold": "pause.circle.fill"
    case "wishlist": "heart.circle.fill"
    case "archived", "destashed": "archivebox.circle.fill"
    case "kitted", "palette_chosen": "checkmark.circle"
    default: "circle.fill"
    }
  }

  /// Hue is never the only signal here: every case pairs with a distinct icon and
  /// its written label, as required by docs/design.md.
  private var tint: Color {
    if onSurface {
      return theme.surfaceForeground
    }
    return switch status {
    case "completed": theme.accent
    case "progress", "in_progress": theme.primary
    case "onhold", "on_hold": theme.destructive
    case "wishlist": theme.primary
    case "archived", "destashed": theme.mutedForeground
    case "kitted", "palette_chosen": theme.accent
    default: theme.mutedForeground
    }
  }
}
