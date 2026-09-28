import SwiftUI

/// Stacked Caveat wordmark used on splash, welcome, and account-entry screens.
struct BrandWordmark: View {
  @Environment(\.theme) private var theme

  var size: CGFloat = 56
  var relativeTo: Font.TextStyle = .largeTitle
  var sparkles: BrandWordmarkArt.Sparkles = .none
  var accessibilityIdentifier: String? = nil

  @ScaledMetric private var scaledSize: CGFloat

  init(
    size: CGFloat = 56,
    relativeTo: Font.TextStyle = .largeTitle,
    sparkles: BrandWordmarkArt.Sparkles = .none,
    accessibilityIdentifier: String? = nil
  ) {
    self.size = size
    self.relativeTo = relativeTo
    self.sparkles = sparkles
    self.accessibilityIdentifier = accessibilityIdentifier
    _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
  }

  var body: some View {
    BrandWordmarkArt(
      size: scaledSize,
      foreground: theme.foreground,
      primary: theme.primary,
      accent: theme.accent,
      sparkles: sparkles
    )
    .frame(maxWidth: .infinity)
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Organized Glitter")
    .accessibilityAddTraits(.isHeader)
    .accessibilityIdentifier(accessibilityIdentifier ?? "brandWordmark")
  }
}

/// Bounded primary action shared by welcome, forms, and recovery screens.
struct AuthPrimaryButtonStyle: ButtonStyle {
  @Environment(\.theme) private var theme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.semibold))
      .multilineTextAlignment(.center)
      .foregroundStyle(theme.primaryForeground)
      .tint(theme.primaryForeground)
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .frame(
        maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 280,
        minHeight: AccountEntryLayout.primaryButtonHeight
      )
      .background(theme.primary, in: .rect(cornerRadius: 12))
      .opacity(!isEnabled ? 0.5 : (configuration.isPressed ? 0.8 : 1))
      .frame(maxWidth: .infinity)
  }
}

struct AuthSubmitLabel: View {
  let title: String
  let isSubmitting: Bool

  var body: some View {
    Text(title)
      .opacity(isSubmitting ? 0 : 1)
      .overlay {
        if isSubmitting {
          ProgressView()
            .accessibilityHidden(true)
        }
      }
      .accessibilityLabel(title)
      .accessibilityValue(isSubmitting ? "In progress" : "")
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
      .frame(maxWidth: .infinity, minHeight: AccountEntryLayout.secondaryButtonHeight)
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
  var contentWidth: CGFloat = 360
  var fillsHeight: Bool = false
  /// Paints the flat launch color over the themed background.
  var coversBackground: Bool = false
  @ViewBuilder let content: Content

  var body: some View {
    GeometryReader { proxy in
      ScrollView {
        content
          .frame(maxWidth: contentWidth, alignment: Alignment(horizontal: alignment, vertical: .center))
          .padding(.horizontal, 28)
          .padding(.top, AccountEntryLayout.topPadding)
          .padding(.bottom, AccountEntryLayout.bottomPadding)
          .frame(
            maxWidth: .infinity,
            minHeight: fillsHeight ? proxy.size.height : nil,
            alignment: fillsHeight ? .center : .top
          )
      }
      .scrollClipDisabled()
    }
    .scrollDismissesKeyboard(.interactively)
    .background {
      theme.themedBackground
        .overlay(theme.background.opacity(coversBackground ? 1 : 0))
        .ignoresSafeArea()
    }
  }
}
