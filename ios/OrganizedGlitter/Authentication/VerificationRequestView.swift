import SwiftUI

/// Requests a verification email for an existing unverified account.
struct VerificationRequestView: View {
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

        Text(didRequest ? "Check your inbox" : "Verify email")
          .font(.title2.weight(.semibold))
          .foregroundStyle(theme.foreground)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("verificationTitle")

        if didRequest {
          confirmationContent
        } else {
          requestForm
        }

        Button("Back to sign in") { dismiss() }
          .buttonStyle(AuthLinkButtonStyle())
          .accessibilityIdentifier("verificationBack")
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if email.isEmpty {
        email = initialEmail
      }
    }
    .onDisappear {
      submitGeneration += 1
      isEmailFocused = false
    }
  }

  @ViewBuilder
  private var confirmationContent: some View {
    VStack(spacing: 12) {
      Text("If that account exists, a verification email is on its way.")
        .font(.body)
        .multilineTextAlignment(.center)
        .foregroundStyle(theme.foreground)
        .accessibilityIdentifier("verificationConfirmation")

      Text(
        "Open the verification link from email to finish. Native confirmation through a universal link is not available in this app yet."
      )
      .font(.footnote)
      .multilineTextAlignment(.center)
      .foregroundStyle(theme.mutedForeground)
    }
  }

  @ViewBuilder
  private var requestForm: some View {
    Text("Enter the email for your Organized Glitter account to request a new verification message.")
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
        .accessibilityIdentifier("verificationEmail")
    }

    if let errorMessage {
      AccessibleErrorLabel(message: errorMessage)
        .accessibilityIdentifier("verificationError")
    }

    Button {
      Task { await send() }
    } label: {
      if isSending {
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 52)
      } else {
        Text("Send verification email")
      }
    }
    .buttonStyle(AuthPrimaryButtonStyle())
    .disabled(isSending || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    .accessibilityIdentifier("verificationSend")
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
      try await client.requestVerification(email: normalized)
      guard generation == submitGeneration else { return }
      didRequest = true
    } catch APIError.cancelled {
      return
    } catch APIError.offline {
      guard generation == submitGeneration else { return }
      errorMessage = "You appear to be offline. Reconnect and try again."
    } catch {
      guard generation == submitGeneration else { return }
      errorMessage = "The verification email could not be sent. Try again."
    }
  }
}
