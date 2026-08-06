import SwiftUI

struct SignInView: View {
  @Environment(\.theme) private var theme

  let model: AppModel

  @State private var identity = ""
  @State private var password = ""
  @FocusState private var focusedField: Field?

  private enum Field {
    case identity
    case password
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        VStack(alignment: .leading, spacing: 8) {
          Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)

          Text("Organized Glitter")
            .font(.caveat(size: 44))
            .foregroundStyle(theme.foreground)

          Text("Your private craft library, right where you left it.")
            .font(.body)
            .foregroundStyle(theme.mutedForeground)
        }

        VStack(spacing: 16) {
          TextField("Email address", text: $identity)
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .focused($focusedField, equals: .identity)
            .onSubmit { focusedField = .password }

          SecureField("Password", text: $password)
            .textContentType(.password)
            .submitLabel(.go)
            .focused($focusedField, equals: .password)
            .onSubmit(signIn)

          if let error = model.signInError {
            Label(error, systemImage: "exclamationmark.circle")
              .font(.footnote)
              .foregroundStyle(.red)
              .frame(maxWidth: .infinity, alignment: .leading)
              .accessibilityIdentifier("signInError")
          }

          Button(action: signIn) {
            if model.isSubmitting {
              ProgressView()
                .frame(maxWidth: .infinity)
            } else {
              Text("Sign In")
                .frame(maxWidth: .infinity)
            }
          }
          .buttonStyle(PillButtonStyle())
          .disabled(model.isSubmitting)
          .accessibilityIdentifier("signInButton")

          NavigationLink("Forgot password?") {
            if let client = model.client {
              PasswordResetView(client: client, initialEmail: identity)
            }
          }
          .accessibilityLabel("Reset a forgotten password")

          NavigationLink("Create an account") {
            if let client = model.client {
              RegistrationView(client: client)
            }
          }
          .accessibilityLabel("Create an Organized Glitter account")

          NavigationLink("Resend verification email") {
            if let client = model.client {
              VerificationRequestView(client: client, initialEmail: identity)
            }
          }
          .accessibilityLabel("Request a new verification email")
        }
        .textFieldStyle(.roundedBorder)
      }
      .frame(maxWidth: 420)
      .padding(32)
      .frame(maxWidth: .infinity)
    }
    .background(theme.backgroundGradient)
    .onAppear { focusedField = .identity }
  }

  private func signIn() {
    Task {
      await model.signIn(identity: identity, password: password)
    }
  }
}
