import SwiftUI
import UIKit
import Observation

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
  /// system defaults: Liquid Glass and the scroll edge effect draw the
  /// transparent bar.
  static func applyCaveatLargeTitles() {
    guard let caveat = UIFont(name: "Caveat", size: 44) else { return }
    let scaledFont = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: caveat)
    let titleStrokeClearance = scaledFont.pointSize / 11
    let attributes: [NSAttributedString.Key: Any] = [
      .font: scaledFont,
      .kern: titleStrokeClearance,
      .foregroundColor: UIColor { traits in
        UIColor(traits.userInterfaceStyle == .dark ? Theme.dark.foreground : Theme.light.foreground)
      },
    ]
    let standard = UINavigationBarAppearance()
    let scrollEdge = UINavigationBarAppearance()
    scrollEdge.configureWithTransparentBackground()
    standard.configureWithTransparentBackground()
    var inlineAttributes = attributes
    inlineAttributes.removeValue(forKey: .kern)
    inlineAttributes[.font] = KarlaTypography.nativeFont(size: 17, relativeTo: .headline)
    standard.titleTextAttributes = inlineAttributes
    scrollEdge.titleTextAttributes = inlineAttributes
    standard.largeTitleTextAttributes = attributes
    scrollEdge.largeTitleTextAttributes = attributes
    appearance().standardAppearance = standard
    appearance().compactAppearance = standard
    appearance().scrollEdgeAppearance = scrollEdge
  }
}

/// The page background. Light paints the palette's `backgroundGradient`.
/// Dark paints a flat navy base with the palette's `backgroundBloom` over it. The opaque base keeps nested
/// backgrounds from doubling up the bloom.
struct ThemeBackground: View {
  let theme: Theme

  var body: some View {
    if let bloom = theme.backgroundBloom {
      GeometryReader { geo in
        let radiusX = max(geo.size.width * bloom.radiusFraction.width, 1)
        let radiusY = geo.size.height * bloom.radiusFraction.height

        RadialGradient(
          stops: bloom.stops.map { Gradient.Stop(color: $0.color, location: $0.location) },
          center: .center,
          startRadius: 0,
          endRadius: radiusX
        )
        .frame(width: radiusX * 2, height: radiusX * 2)
        .scaleEffect(x: 1, y: radiusY / radiusX)
        .position(x: geo.size.width * bloom.center.x, y: geo.size.height * bloom.center.y)
      }
      .background(theme.background)
      .clipped()
    } else {
      theme.backgroundGradient
    }
  }
}

/// Replaces the stock grouped-list grey with the themed background surface.
/// Section headers and footers draw in the secondary style directly over the
/// page, so it resolves to the page text color to stay readable on the gradient.
struct ThemedScrollBackground: ViewModifier {
  @Environment(\.theme) private var theme

  func body(content: Content) -> some View {
    content
      .scrollContentBackground(.hidden)
      .foregroundStyle(theme.foreground, theme.pageSecondaryForeground)
      .background(theme.themedBackground.ignoresSafeArea())
  }
}

extension View {
  func themedScrollBackground() -> some View {
    modifier(ThemedScrollBackground())
  }
}

@MainActor
@Observable
final class FormDrawer {
  struct Route {
    let id = UUID()
    let detents: Set<PresentationDetent>
    let content: AnyView
    let onDismiss: () -> Void
  }

  var route: Route?
  var isPresenting: Bool { route != nil }

  @discardableResult
  func present<Content: View>(
    detents: Set<PresentationDetent>,
    onDismiss: @escaping () -> Void = {},
    @ViewBuilder content: () -> Content
  ) -> Bool {
    guard route == nil else { return false }
    route = Route(detents: detents, content: AnyView(content()), onDismiss: onDismiss)
    return true
  }

  func dismiss() {
    let onDismiss = route?.onDismiss
    route = nil
    onDismiss?()
  }

}

extension View {
  func disabledWhileFormPresented(_ drawer: FormDrawer, or isDisabled: Bool = false) -> some View {
    disabled(isDisabled || drawer.isPresenting)
  }

  func formDrawerHost(_ drawer: FormDrawer) -> some View {
    inspector(isPresented: Binding(
      get: { drawer.route != nil },
      set: { if !$0 { drawer.dismiss() } }
    )) {
      if let route = drawer.route {
        route.content
          .id(route.id)
          .inspectorColumnWidth(min: 320, ideal: 400, max: 480)
          .presentationDetents(route.detents)
          .presentationDragIndicator(.visible)
      }
    }
    .environment(drawer)
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
      .font(.karla(.caption).weight(.semibold))
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

/// A quiet native control without movement on press.
struct QuietActionStyle: ButtonStyle {
  @Environment(\.theme) private var theme
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .labelStyle(.titleAndIcon)
      .font(.karla(.body).weight(.medium))
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

extension View {
  func glassButton() -> some View {
    buttonStyle(.glass)
  }

  func glassProminentButton() -> some View {
    buttonStyle(.glassProminent)
  }
}
