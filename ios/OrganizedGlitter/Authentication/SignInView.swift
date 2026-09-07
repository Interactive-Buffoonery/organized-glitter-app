import SwiftUI

/// Email and password sign-in. Provider method selection is deferred until
/// Apple, Google, and Discord continuity is verified against production.
struct SignInView: View {
  @Environment(\.theme) private var theme

  let model: AppModel

  @State private var identity = ""
  @State private var password = ""
  @State private var submitGeneration = 0
  @FocusState private var focusedField: Field?

  private enum Field {
    case identity
    case password
  }

  var body: some View {
    AuthEntryContainer(alignment: .leading) {
      VStack(alignment: .leading, spacing: 24) {
        Text("Sign in with email")
          .font(.title2.weight(.semibold))
          .foregroundStyle(theme.foreground)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("signInTitle")

        AuthLabeledField(title: "Email") {
          TextField("you@example.com", text: $identity)
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .focused($focusedField, equals: .identity)
            .onSubmit { focusedField = .password }
            .accessibilityIdentifier("signInEmail")
        }

        AuthLabeledField(title: "Password") {
          SecureField("Password", text: $password)
            .textContentType(.password)
            .submitLabel(.go)
            .focused($focusedField, equals: .password)
            .onSubmit(signIn)
            .accessibilityIdentifier("signInPassword")
        }

        if let error = model.signInError {
          AccessibleErrorLabel(message: error)
            .accessibilityIdentifier("signInError")
        }

        Button(action: signIn) {
          if model.isSubmitting {
            ProgressView()
              .frame(maxWidth: .infinity, minHeight: 52)
          } else {
            Text("Sign in")
          }
        }
        .buttonStyle(AuthPrimaryButtonStyle())
        .disabled(model.isSubmitting || model.client == nil)
        .accessibilityIdentifier("signInButton")

        HStack(spacing: 20) {
          NavigationLink {
            if let client = model.client {
              PasswordResetView(client: client, initialEmail: identity)
            }
          } label: {
            Text("Forgot password?")
          }
          .buttonStyle(AuthLinkButtonStyle())
          .accessibilityLabel("Reset a forgotten password")
          .disabled(model.client == nil)

          NavigationLink {
            if let client = model.client {
              VerificationRequestView(client: client, initialEmail: identity)
            }
          } label: {
            Text("Resend verification")
          }
          .buttonStyle(AuthLinkButtonStyle())
          .accessibilityLabel("Request a new verification email")
          .disabled(model.client == nil)
        }
        .frame(maxWidth: .infinity)

        privacyAndTermsLinks
          .frame(maxWidth: .infinity)

        HStack(spacing: 6) {
          Text("New to Organized Glitter?")
            .font(.subheadline)
            .foregroundStyle(theme.mutedForeground)
          NavigationLink {
            RegistrationView(client: model.client)
          } label: {
            Text("Create account")
          }
          .buttonStyle(AuthLinkButtonStyle())
          .disabled(model.client == nil)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      model.signInError = nil
      focusedField = .identity
    }
    .onDisappear {
      submitGeneration += 1
    }
  }

  private var privacyAndTermsLinks: some View {
    HStack(spacing: 20) {
      Link("Privacy", destination: AccountLinks.privacy)
        .buttonStyle(AuthLinkButtonStyle())
        .accessibilityLabel("Open privacy policy")
      Link("Terms", destination: AccountLinks.terms)
        .buttonStyle(AuthLinkButtonStyle())
        .accessibilityLabel("Open terms of service")
    }
  }

  private func signIn() {
    submitGeneration += 1
    let generation = submitGeneration
    Task {
      await model.signIn(identity: identity, password: password)
      if generation != submitGeneration {
        return
      }
    }
  }
}
