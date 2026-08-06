import SwiftUI

struct RegistrationView: View {
  @Environment(\.theme) private var theme
  let client: PocketBaseClient

  @State private var email = ""
  @State private var username = ""
  @State private var password = ""
  @State private var passwordConfirmation = ""
  @State private var isSubmitting = false
  @State private var message: String?

  var body: some View {
    Form {
      Section {
        TextField("Email address", text: $email)
          .textContentType(.emailAddress)
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        TextField("Username", text: $username)
          .textContentType(.username)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        SecureField("Password", text: $password)
          .textContentType(.newPassword)
        SecureField("Confirm password", text: $passwordConfirmation)
          .textContentType(.newPassword)
      } footer: {
        Text("Use at least 8 characters for your password. Usernames must be 4–25 letters, numbers, hyphens, or underscores.")
      }

      if let message {
        Section { Text(message).foregroundStyle(theme.foreground) }
      }

      Section {
        Button("Create Account") { Task { await register() } }
          .disabled(isSubmitting)
          .accessibilityIdentifier("createAccountButton")
      }
    }
    .themedScrollBackground()
    .navigationTitle("Create Account")
  }

  private func register() async {
    let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedEmail.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil else {
      message = "Enter a valid email address."
      return
    }
    guard normalizedUsername.range(of: #"^[A-Za-z0-9_-]{4,25}$"#, options: .regularExpression) != nil else {
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

    isSubmitting = true
    message = nil
    defer { isSubmitting = false }
    do {
      try await client.register(
        email: normalizedEmail,
        username: normalizedUsername,
        password: password
      )
      password = ""
      passwordConfirmation = ""
      do {
        try await client.requestVerification(email: normalizedEmail)
        message = "Your account is ready. Check your email to verify it before signing in."
      } catch APIError.cancelled {
        return
      } catch {
        message = "Your account is ready, but the verification email could not be sent. Use Resend Verification Email from the sign-in screen."
      }
    } catch APIError.cancelled {
      return
    } catch {
      message = "Your account could not be created. Check your details and try again."
    }
  }
}

struct VerificationRequestView: View {
  let client: PocketBaseClient
  let initialEmail: String

  @State private var email = ""
  @State private var isSending = false
  @State private var message: String?

  var body: some View {
    Form {
      TextField("Email address", text: $email)
        .textContentType(.emailAddress)
        .keyboardType(.emailAddress)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()

      if let message { Text(message) }

      Button("Send Verification Email") { Task { await send() } }
        .disabled(isSending || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    .themedScrollBackground()
    .navigationTitle("Verify Email")
    .onAppear { email = initialEmail }
  }

  private func send() async {
    isSending = true
    message = nil
    defer { isSending = false }
    do {
      try await client.requestVerification(
        email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
      message = "If that account exists, a verification email is on its way."
    } catch APIError.cancelled {
      return
    } catch {
      message = "The verification email could not be sent. Try again."
    }
  }
}

struct ProfileNameView: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable var preferences: AccountPreferencesModel
  @State private var name = ""

  var body: some View {
    Form {
      TextField("Profile name", text: $name)
        .textContentType(.nickname)
        .autocorrectionDisabled()
        .accessibilityLabel("Profile name")
    }
    .navigationTitle("Profile Name")
    .toolbar {
      Button("Save") {
        Task {
          if await preferences.updateProfile(username: name) {
            dismiss()
          }
        }
      }
      .disabled(
        preferences.isSaving
          || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .accessibilityLabel("Save profile name")
    }
    .onAppear {
      name = preferences.user.username ?? preferences.user.name ?? ""
    }
  }
}

struct PasswordResetView: View {
  @Environment(\.theme) private var theme
  let client: PocketBaseClient
  let initialEmail: String

  @State private var email = ""
  @State private var isSending = false
  @State private var message: String?

  var body: some View {
    Form {
      Section {
        TextField("Email address", text: $email)
          .textContentType(.emailAddress)
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .accessibilityLabel("Password reset email address")
      } footer: {
        Text("We’ll email a password reset link. Native link confirmation will be added after the universal-link contract is verified.")
      }

      if let message {
        Section {
          Text(message)
            .foregroundStyle(theme.foreground)
            .accessibilityLabel(message)
        }
      }

      Section {
        Button("Send Reset Link") {
          Task { await send() }
        }
        .disabled(
          isSending || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel("Send password reset link")
      }
    }
    .themedScrollBackground()
    .navigationTitle("Reset Password")
    .onAppear { email = initialEmail }
  }

  private func send() async {
    isSending = true
    message = nil
    defer { isSending = false }

    do {
      try await client.requestPasswordReset(
        email: email.trimmingCharacters(in: .whitespacesAndNewlines))
      message = "If that account exists, a reset link is on its way."
    } catch APIError.cancelled {
      return
    } catch {
      message = "The reset link could not be sent. Try again."
    }
  }
}

struct AppInformationView: View {
  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "Unknown"
  }

  private var build: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
  }

  var body: some View {
    List {
      LabeledContent("App", value: "Organized Glitter")
      LabeledContent("Version", value: version)
      LabeledContent("Build", value: build)
      Text("A private craft-project library for iPhone and iPad.")
        .fixedSize(horizontal: false, vertical: true)
    }
    .navigationTitle("App Information")
  }
}

enum AccountLinks {
  static let privacy = URL(string: "https://organizedglitter.app/privacy")!
  static let terms = URL(string: "https://organizedglitter.app/terms")!
  static let support = URL(string: "mailto:support@organizedglitter.app")!
  static let accountDeletionSupport = URL(
    string: "mailto:support@organizedglitter.app?subject=Account%20Deletion%20Help"
  )!
  static let feedback = URL(
    string:
      "mailto:support@organizedglitter.app?subject=Organized%20Glitter%20iOS%20Feedback"
  )!
}
