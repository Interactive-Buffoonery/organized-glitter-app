import CoreText
import SwiftUI
import UIKit

/// Stacked Caveat wordmark used on splash, welcome, and account-entry screens.
///
/// SwiftUI `Text` and UILabel both clip Caveat’s ascenders against a tight
/// typographic line box. Draw each line with Core Text using glyph-path bounds
/// so the script stays whole, and shrink to fit the available width.
struct BrandWordmark: View {
  @Environment(\.theme) private var theme

  var size: CGFloat = 56
  var relativeTo: Font.TextStyle = .largeTitle
  var accessibilityIdentifier: String? = nil

  @ScaledMetric private var scaledSize: CGFloat

  init(
    size: CGFloat = 56,
    relativeTo: Font.TextStyle = .largeTitle,
    accessibilityIdentifier: String? = nil
  ) {
    self.size = size
    self.relativeTo = relativeTo
    self.accessibilityIdentifier = accessibilityIdentifier
    _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
  }

  var body: some View {
    VStack(spacing: scaledSize * 0.08) {
      CaveatWordmarkLine(text: "Organized", pointSize: scaledSize, color: theme.foreground)
      CaveatWordmarkLine(text: "Glitter", pointSize: scaledSize, color: theme.foreground)
    }
    .frame(maxWidth: .infinity)
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Organized Glitter")
    .accessibilityAddTraits(.isHeader)
    .accessibilityIdentifier(accessibilityIdentifier ?? "brandWordmark")
  }
}

private struct CaveatWordmarkLine: UIViewRepresentable {
  var text: String
  var pointSize: CGFloat
  var color: Color

  func makeUIView(context: Context) -> CaveatWordmarkLabel {
    CaveatWordmarkLabel()
  }

  func updateUIView(_ label: CaveatWordmarkLabel, context: Context) {
    label.wordmarkText = text
    label.pointSize = pointSize
    label.ink = UIColor(color)
    label.setNeedsDisplay()
    label.invalidateIntrinsicContentSize()
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiView: CaveatWordmarkLabel,
    context: Context
  ) -> CGSize? {
    uiView.preferredSize(forWidth: proposal.width)
  }
}

private final class CaveatWordmarkLabel: UIView {
  var wordmarkText: String = ""
  var pointSize: CGFloat = 56
  var ink: UIColor = .label

  override init(frame: CGRect) {
    super.init(frame: frame)
    isOpaque = false
    backgroundColor = .clear
    contentMode = .redraw
    clipsToBounds = false
    setContentHuggingPriority(.required, for: .vertical)
    setContentCompressionResistancePriority(.required, for: .vertical)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private var baseFont: UIFont {
    UIFont(name: "Caveat-Regular", size: pointSize)
      ?? UIFont(name: "Caveat", size: pointSize)
      ?? .systemFont(ofSize: pointSize)
  }

  private func glyphBounds(for font: UIFont) -> CGRect {
    let attributed = NSAttributedString(
      string: wordmarkText,
      attributes: [.font: font]
    )
    let line = CTLineCreateWithAttributedString(attributed)
    return CTLineGetBoundsWithOptions(
      line,
      [.useGlyphPathBounds, .useOpticalBounds]
    )
  }

  func preferredSize(forWidth width: CGFloat?) -> CGSize {
    let font = baseFont
    let bounds = glyphBounds(for: font)
    let pad = font.pointSize * 0.08
    var size = CGSize(
      width: ceil(bounds.width + pad * 2),
      height: ceil(bounds.height + pad * 2)
    )
    if let width, width > 0, width.isFinite, size.width > width {
      let scale = width / size.width
      size = CGSize(width: width, height: ceil(size.height * scale))
    }
    return size
  }

  override var intrinsicContentSize: CGSize {
    preferredSize(forWidth: nil)
  }

  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext(), !wordmarkText.isEmpty else { return }
    let font = baseFont
    let attributed = NSAttributedString(
      string: wordmarkText,
      attributes: [
        .font: font,
        .foregroundColor: ink,
      ]
    )
    let line = CTLineCreateWithAttributedString(attributed)
    let glyphBounds = CTLineGetBoundsWithOptions(
      line,
      [.useGlyphPathBounds, .useOpticalBounds]
    )
    let naturalWidth = max(glyphBounds.width, 1)
    let naturalHeight = max(glyphBounds.height, 1)
    let scale = min(
      bounds.width / naturalWidth,
      bounds.height / naturalHeight,
      1
    )

    context.saveGState()
    context.textMatrix = .identity
    context.translateBy(x: bounds.midX, y: bounds.midY)
    context.scaleBy(x: scale, y: -scale)
    context.textPosition = CGPoint(
      x: -glyphBounds.midX,
      y: -glyphBounds.midY
    )
    CTLineDraw(line, context)
    context.restoreGState()
  }
}

/// Quiet primary action for account entry: full-width, no sticker chrome.
/// Light uses the soft secondary wash; dark uses the elevated card fill so the
/// control stays readable over the navy glow without a loud brand pill.
struct AuthPrimaryButtonStyle: ButtonStyle {
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    let fill: Color = {
      if colorScheme == .dark {
        return configuration.isPressed ? theme.muted : theme.card
      }
      return configuration.isPressed ? theme.muted : theme.secondary
    }()

    configuration.label
      .font(.body.weight(.semibold))
      .foregroundStyle(theme.foreground)
      .frame(maxWidth: .infinity, minHeight: 52)
      .padding(.horizontal, 18)
      .background(fill, in: .rect(cornerRadius: 16))
      .overlay {
        RoundedRectangle(cornerRadius: 16)
          .stroke(theme.border, lineWidth: 1)
      }
      .opacity(isEnabled ? 1 : 0.5)
  }
}

/// Text-style secondary action used under the welcome primary button.
struct AuthSecondaryButtonStyle: ButtonStyle {
  @Environment(\.theme) private var theme
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.medium))
      .foregroundStyle(theme.foreground)
      .frame(maxWidth: .infinity, minHeight: 48)
      .opacity(configuration.isPressed || !isEnabled ? 0.55 : 1)
  }
}

/// Underlined quiet link used on account-entry forms.
struct AuthLinkButtonStyle: ButtonStyle {
  @Environment(\.theme) private var theme

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.subheadline.weight(.medium))
      .foregroundStyle(theme.primary)
      .underline(true, color: theme.primary)
      .opacity(configuration.isPressed ? 0.6 : 1)
      .frame(minHeight: 44)
  }
}

/// Labeled account-entry field with a native rounded surface.
struct AuthLabeledField<Content: View>: View {
  @Environment(\.theme) private var theme

  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(theme.foreground)
      content
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(minHeight: 52)
        .background(theme.card, in: .rect(cornerRadius: 12))
        .overlay {
          RoundedRectangle(cornerRadius: 12)
            .stroke(theme.border, lineWidth: 1)
        }
    }
  }
}

/// Shared account-entry scroll shell: continuous themed background, readable width.
struct AuthEntryContainer<Content: View>: View {
  @Environment(\.theme) private var theme

  var alignment: HorizontalAlignment = .center
  var fillsHeight: Bool = false
  @ViewBuilder let content: Content

  var body: some View {
    GeometryReader { proxy in
      ScrollView {
        content
          .frame(maxWidth: 420, alignment: Alignment(horizontal: alignment, vertical: .center))
          .padding(.horizontal, 28)
          .padding(.top, 24)
          .padding(.bottom, 36)
          .frame(
            maxWidth: .infinity,
            minHeight: fillsHeight ? proxy.size.height : nil,
            alignment: fillsHeight ? .center : .top
          )
      }
      .scrollClipDisabled()
    }
    .scrollDismissesKeyboard(.interactively)
    .background(theme.themedBackground.ignoresSafeArea())
  }
}
