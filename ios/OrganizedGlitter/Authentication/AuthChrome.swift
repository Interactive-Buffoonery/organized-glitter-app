import SwiftUI

/// Stacked Caveat wordmark used on splash, welcome, and account-entry screens.
struct BrandWordmark: View {
  @Environment(\.theme) private var theme

  var size: CGFloat = 56
  var relativeTo: Font.TextStyle = .largeTitle
  var accessibilityIdentifier: String? = nil

  var body: some View {
    VStack(spacing: 0) {
      Text("Organized")
      Text("Glitter")
    }
    .font(.caveat(size: size, relativeTo: relativeTo))
    .foregroundStyle(theme.foreground)
    .multilineTextAlignment(.center)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Organized Glitter")
    .accessibilityAddTraits(.isHeader)
    .accessibilityIdentifier(accessibilityIdentifier ?? "brandWordmark")
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
    }
    .scrollDismissesKeyboard(.interactively)
    .background(theme.themedBackground.ignoresSafeArea())
  }
}
