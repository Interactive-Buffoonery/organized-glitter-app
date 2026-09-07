import SwiftUI

struct RegistrationView: View {
  @Environment(\.theme) private var theme

  let client: PocketBaseClient?
  @Binding var path: NavigationPath

  @State private var email = ""
  @State private var username = ""
  @State private var password = ""
  @State private var passwordConfirmation = ""
  @State private var isSubmitting = false
  @State private var message: String?
  @State private var didSucceed = false
  @State private var submitGeneration = 0
  @FocusState private var focusedField: Field?

  init(client: PocketBaseClient?, path: Binding<NavigationPath>) {
    self.client = client
    self._path = path
  }

  private enum Field {
    case username
    case email
    case password
    case confirmation
  }

  var body: some View {
    AuthEntryContainer(alignment: .leading) {
      VStack(alignment: .leading, spacing: 24) {
        Text(didSucceed ? "Check your inbox" : "Create account with email")
          .font(.title2.weight(.semibold))
          .foregroundStyle(theme.foreground)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("registrationTitle")

        if didSucceed {
          successContent
        } else {
          formContent
        }
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { focusedField = nil }
    .onDisappear { submitGeneration += 1 }
  }

  @ViewBuilder
  private var successContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(
        message
          ?? "Your account is ready. Check your email to verify it before signing in."
      )
      .font(.body)
      .foregroundStyle(theme.foreground)
      .accessibilityIdentifier("registrationSuccess")

      Text("Verification confirmation through a universal link is not available in this app yet. Open the link from email on the web, or request another verification email from Sign in.")
        .font(.footnote)
        .foregroundStyle(theme.mutedForeground)

      Button("Back to welcome") {
        path = NavigationPath()
      }
        .buttonStyle(AuthPrimaryButtonStyle())
        .accessibilityIdentifier("registrationBackToWelcome")
    }
  }

  @ViewBuilder
  private var formContent: some View {
    AuthLabeledField(title: "Username") {
      TextField("crafty_name", text: $username)
        .textContentType(.username)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.next)
        .focused($focusedField, equals: .username)
        .onSubmit { focusedField = .email }
        .accessibilityIdentifier("registrationUsername")
    }

    AuthLabeledField(title: "Email") {
      TextField("you@example.com", text: $email)
        .textContentType(.emailAddress)
        .keyboardType(.emailAddress)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.next)
        .focused($focusedField, equals: .email)
        .onSubmit { focusedField = .password }
        .accessibilityIdentifier("registrationEmail")
    }

    AuthLabeledField(title: "Password") {
      SecureField("At least 8 characters", text: $password)
        .textContentType(.newPassword)
        .submitLabel(.next)
        .focused($focusedField, equals: .password)
        .onSubmit { focusedField = .confirmation }
        .accessibilityIdentifier("registrationPassword")
    }

    AuthLabeledField(title: "Confirm password") {
      SecureField("Confirm password", text: $passwordConfirmation)
        .textContentType(.newPassword)
        .submitLabel(.go)
        .focused($focusedField, equals: .confirmation)
        .onSubmit { Task { await register() } }
        .accessibilityIdentifier("registrationPasswordConfirm")
    }

    Text("Use at least 8 characters for your password. Usernames must be 4–25 letters, numbers, hyphens, or underscores.")
      .font(.footnote)
      .foregroundStyle(theme.mutedForeground)

    if let message, !didSucceed {
      AccessibleErrorLabel(message: message)
        .accessibilityIdentifier("registrationError")
    }

    Button {
      Task { await register() }
    } label: {
      if isSubmitting {
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 52)
      } else {
        Text("Create account")
      }
    }
    .buttonStyle(AuthPrimaryButtonStyle())
    .disabled(isSubmitting || client == nil)
    .accessibilityIdentifier("createAccountButton")

    Text("By creating an account you agree to the Privacy Policy and Terms of Service.")
      .font(.footnote)
      .foregroundStyle(theme.mutedForeground)

    HStack(spacing: 20) {
      Link("Privacy", destination: AccountLinks.privacy)
        .buttonStyle(AuthLinkButtonStyle())
      Link("Terms", destination: AccountLinks.terms)
        .buttonStyle(AuthLinkButtonStyle())
    }
    .frame(maxWidth: .infinity)

    HStack(spacing: 6) {
      Text("Already have an account?")
        .font(.subheadline)
        .foregroundStyle(theme.mutedForeground)
      Button("Sign in") {
        path = NavigationPath()
        path.append(AccountEntryRoute.methods(.signIn))
      }
      .buttonStyle(AuthLinkButtonStyle())
      .accessibilityLabel("Back to sign in")
      .accessibilityIdentifier("registrationSignIn")
    }
    .frame(maxWidth: .infinity)
    .padding(.bottom, 24)
  }

  private func register() async {
    guard let client else {
      message = "Organized Glitter is not configured for account creation."
      return
    }

    let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedEmail.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    else {
      message = "Enter a valid email address."
      return
    }
    guard normalizedUsername.range(of: #"^[A-Za-z0-9_-]{4,25}$"#, options: .regularExpression) != nil
    else {
      message = "Use 4–25 letters, numbers, hyphens, or underscores for your username."
      return
    }
    guard password.count >= 8 else {
      message = "Use at least 8 characters for your password."
      return
    }
    guard password == passwordConfirmation else {
      message = "Passwords do not match."
      return
    }

    submitGeneration += 1
    let generation = submitGeneration
    isSubmitting = true
    message = nil
    defer {
      if generation == submitGeneration {
        isSubmitting = false
      }
    }

    do {
      try await client.register(
        email: normalizedEmail,
        username: normalizedUsername,
        password: password
      )
      guard generation == submitGeneration else { return }
      password = ""
      passwordConfirmation = ""
      do {
        try await client.requestVerification(email: normalizedEmail)
        guard generation == submitGeneration else { return }
        message = "Your account is ready. Check your email to verify it before signing in."
        didSucceed = true
      } catch APIError.cancelled {
        return
      } catch {
        guard generation == submitGeneration else { return }
        message =
          "Your account is ready, but the verification email could not be sent. Use Resend verification from Sign in."
        didSucceed = true
      }
    } catch APIError.cancelled {
      return
    } catch {
      guard generation == submitGeneration else { return }
      message = "Your account could not be created. Check your details and try again."
    }
  }
}
