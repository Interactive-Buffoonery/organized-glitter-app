import SwiftUI

/// Requests a password-reset email. Token confirmation stays blocked until the
/// backend ships Associated Domains and universal-link routes.
struct PasswordResetView: View {
  @Environment(\.theme) private var theme
  @Environment(\.dismiss) private var dismiss

  let client: PocketBaseClient
  let initialEmail: String

  @State private var email = ""
  @State private var isSending = false
  @State private var didRequest = false
  @State private var errorMessage: String?
  @State private var submitGeneration = 0
  @FocusState private var isEmailFocused: Bool

  var body: some View {
    AuthEntryContainer(alignment: .center) {
      VStack(spacing: 24) {
        BrandWordmark(size: 48, relativeTo: .title)
          .frame(maxWidth: .infinity)

        Text(didRequest ? "Check your inbox" : "Reset password")
          .font(.title2.weight(.semibold))
          .foregroundStyle(theme.foreground)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("passwordResetTitle")

        if didRequest {
          confirmationContent
        } else {
          requestForm
        }

        Button("Back to sign in") { dismiss() }
          .buttonStyle(AuthLinkButtonStyle())
          .accessibilityIdentifier("passwordResetBack")
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if email.isEmpty {
        email = initialEmail
      }
      isEmailFocused = true
    }
    .onDisappear { submitGeneration += 1 }
  }

  @ViewBuilder
  private var confirmationContent: some View {
    VStack(spacing: 12) {
      Text("If an account exists for that address, you will receive reset instructions.")
        .font(.body)
        .multilineTextAlignment(.center)
        .foregroundStyle(theme.foreground)
        .accessibilityIdentifier("passwordResetConfirmation")

      Text(
        "Opening the reset link inside this app requires a backend universal-link contract that is not available yet. Use the link from email in a browser for now."
      )
      .font(.footnote)
      .multilineTextAlignment(.center)
      .foregroundStyle(theme.mutedForeground)
    }
  }

  @ViewBuilder
  private var requestForm: some View {
    Text("Enter your email and we’ll send you a reset link.")
      .font(.body)
      .multilineTextAlignment(.center)
      .foregroundStyle(theme.foreground)

    AuthLabeledField(title: "Email") {
      TextField("you@example.com", text: $email)
        .textContentType(.emailAddress)
        .keyboardType(.emailAddress)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.send)
        .focused($isEmailFocused)
        .onSubmit { Task { await send() } }
        .accessibilityLabel("Password reset email address")
        .accessibilityIdentifier("passwordResetEmail")
    }

    if let errorMessage {
      AccessibleErrorLabel(message: errorMessage)
        .accessibilityIdentifier("passwordResetError")
    }

    Button {
      Task { await send() }
    } label: {
      if isSending {
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 52)
      } else {
        Text("Send reset link")
      }
    }
    .buttonStyle(AuthPrimaryButtonStyle())
    .disabled(isSending || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    .accessibilityLabel("Send password reset link")
    .accessibilityIdentifier("passwordResetSend")
  }

  private func send() async {
    let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard normalized.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    else {
      errorMessage = "Enter a valid email address."
      return
    }

    submitGeneration += 1
    let generation = submitGeneration
    isSending = true
    errorMessage = nil
    defer {
      if generation == submitGeneration {
        isSending = false
      }
    }

    do {
      try await client.requestPasswordReset(email: normalized)
      guard generation == submitGeneration else { return }
      didRequest = true
    } catch APIError.cancelled {
      return
    } catch APIError.offline {
      guard generation == submitGeneration else { return }
      errorMessage = "You appear to be offline. Reconnect and try again."
    } catch {
      guard generation == submitGeneration else { return }
      errorMessage = "The reset link could not be sent. Try again."
    }
  }
}
