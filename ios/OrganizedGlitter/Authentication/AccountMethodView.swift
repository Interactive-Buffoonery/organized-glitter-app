import SwiftUI

/// Method choice before the email form. Only email is offered while Apple,
/// Google, and Discord lack a verified native continuity path.
struct AccountMethodView: View {
  @Environment(\.theme) private var theme

  enum Mode: Hashable {
    case signIn
    case register

    var title: String {
      switch self {
      case .signIn: "Welcome back"
      case .register: "Create account"
      }
    }

    var emailDestinationTitle: String {
      switch self {
      case .signIn, .register: "Continue with email"
      }
    }

    var switchPrompt: String {
      switch self {
      case .signIn: "New to Organized Glitter?"
      case .register: "Already have an account?"
      }
    }

    var switchActionTitle: String {
      switch self {
      case .signIn: "Create account"
      case .register: "Sign in"
      }
    }

    var opposite: Mode {
      switch self {
      case .signIn: .register
      case .register: .signIn
      }
    }
  }

  let model: AppModel
  @Binding var mode: Mode
  @Binding var path: NavigationPath

  var body: some View {
    AuthEntryContainer(fillsHeight: true) {
      VStack(spacing: 24) {
        Spacer(minLength: 12)

        BrandWordmark(size: 52, relativeTo: .largeTitle)
          .frame(maxWidth: .infinity)

        Text(mode.title)
          .font(.title2.weight(.semibold))
          .foregroundStyle(theme.foreground)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("accountMethodTitle")

        VStack(spacing: 12) {
          Button {
            path.append(mode == .signIn ? AccountEntryRoute.emailSignIn : .emailRegister)
          } label: {
            Label(mode.emailDestinationTitle, systemImage: "envelope")
              .labelStyle(.titleAndIcon)
          }
          .buttonStyle(AuthMethodButtonStyle())
          .accessibilityIdentifier("continueWithEmail")
          .disabled(model.client == nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Account providers")

        HStack(spacing: 6) {
          Text(mode.switchPrompt)
            .font(.subheadline)
            .foregroundStyle(theme.mutedForeground)
          Button(mode.switchActionTitle) {
            mode = mode.opposite
          }
          .buttonStyle(AuthLinkButtonStyle())
          .accessibilityIdentifier("accountMethodSwitch")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)

        Spacer(minLength: 12)
      }
      .frame(maxWidth: .infinity)
    }
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// Rounded method-choice control matching the studio’s quiet provider rows.
struct AuthMethodButtonStyle: ButtonStyle {
  @Environment(\.theme) private var theme
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.medium))
      .foregroundStyle(theme.foreground)
      .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
      .padding(.horizontal, 18)
      .background(theme.card, in: .capsule)
      .overlay {
        Capsule().stroke(theme.border, lineWidth: 1)
      }
      .opacity(configuration.isPressed ? 0.85 : (isEnabled ? 1 : 0.5))
  }
}
