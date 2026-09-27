import AuthenticationServices
import SwiftUI

/// Method choice before the email form.
struct AccountMethodView: View {
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme
  @State private var presentationAnchor: UIWindow?
  @State private var appleSourceID = UUID()

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
          #if DEBUG
            if model.appleReadiness == .available {
              appleButton
            }
          #endif

          NavigationLink(value: mode == .signIn ? AccountEntryRoute.emailSignIn : .emailRegister) {
            Label(mode.emailDestinationTitle, systemImage: "envelope")
              .labelStyle(.titleAndIcon)
          }
          .buttonStyle(AuthMethodButtonStyle())
          .accessibilityIdentifier("continueWithEmail")
          .disabled(model.client == nil)

          #if DEBUG
            if model.appleReadiness == .failed {
              Button("Check Apple sign-in again") {
                Task { await model.loadSignInMethods() }
              }
              .buttonStyle(AuthLinkButtonStyle())
              .accessibilityIdentifier("retryAppleReadiness")
            }
            if let error = model.appleError {
              AccessibleErrorLabel(message: error)
                .accessibilityIdentifier("appleSignInError")
            }
          #endif
          ForEach(model.socialProviders, id: \.self) { provider in
            Button {
              guard let presentationAnchor else { return }
              model.signInWithOAuth(provider: provider, anchor: presentationAnchor)
            } label: {
              Label(
                "Continue with \(provider.displayName)",
                systemImage: provider.symbolName
              )
            }
            .buttonStyle(AuthMethodButtonStyle())
            .disabled(model.isSubmitting || presentationAnchor == nil)
            .accessibilityIdentifier("continueWith\(provider.displayName)")
          }
          if let error = model.oauthError {
            AccessibleErrorLabel(message: error)
              .accessibilityIdentifier("oauthError")
          }
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
      .background {
        OAuthPresentationAnchor { presentationAnchor = $0 }
          .frame(width: 0, height: 0)
          .accessibilityHidden(true)
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .task {
      #if DEBUG
        await model.loadSignInMethods()
      #else
        await model.loadSocialProviders()
      #endif
    }
    .onDisappear {
      model.cancelOAuth()
      #if DEBUG
        model.cancelAppleSignIn()
        appleSourceID = UUID()
      #endif
    }
  }

  #if DEBUG
    private var appleButton: some View {
      let sourceID = appleSourceID
      return SignInWithAppleButton(.continue) { request in
        model.configureAppleRequest(request, sourceID: sourceID)
      } onCompletion: { result in
        model.completeAppleAuthorization(AppleAuthorizationOutcome(result), sourceID: sourceID)
      }
      .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
      .frame(maxWidth: .infinity, minHeight: 52)
      .disabled(model.isSubmitting)
      .accessibilityIdentifier("continueWithApple")
      .id(sourceID)
    }
  #endif
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

enum SocialProvider: String, Sendable {
  case google
  case discord

  var displayName: String {
    switch self {
    case .google: "Google"
    case .discord: "Discord"
    }
  }

  var symbolName: String {
    switch self {
    case .google: "globe"
    case .discord: "bubble.left.and.bubble.right"
    }
  }
}
