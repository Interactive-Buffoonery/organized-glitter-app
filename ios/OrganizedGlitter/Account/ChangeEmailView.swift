import SwiftUI

struct ChangeEmailView: View {
  @Environment(\.connectionAvailable) private var connectionAvailable
  @Environment(\.theme) private var theme
  let appModel: AppModel
  let library: LibrarySession
  let client: PocketBaseClient
  let currentEmail: String

  @State private var email = ""
  @State private var isSending = false
  @State private var confirmationEmail: String?
  @State private var errorMessage: String?
  @State private var sendTask: Task<Void, Never>?
  @State private var generation = 0

  var body: some View {
    Form {
      Group {
        Section("New email") {
          TextField("Email address", text: $email, axis: .vertical)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .disabled(isSending)
            .accessibilityLabel("New email address")
            .accessibilityIdentifier("account.newEmail")
          Button("Send confirmation", action: send)
            .disabled(isSending || !connectionAvailable || normalizedEmail.isEmpty
              || appModel.isChangingPassword || appModel.isSigningOut)
            .buttonStyle(AuthPrimaryButtonStyle())
            .accessibilityIdentifier("account.sendEmailConfirmation")
          if !connectionAvailable { NeedsConnectionHint() }
          if isSending { ProgressView("Sending confirmation") }
        }
        if let confirmationEmail {
          Section {
            Text("Check \(confirmationEmail) for a link to confirm the change. Your email stays the same until you confirm.")
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("account.emailConfirmationSent")
          }
        }
        Section {
          Text("Open the confirmation link on the web and enter your current password. If you usually sign in with Apple, Google, or Discord and don't know a password, reset it first.")
            .fixedSize(horizontal: false, vertical: true)
          NavigationLink("Reset password") {
            PasswordResetView(client: client, initialEmail: currentEmail)
          }
          .disabled(isSending)
        }
        if let errorMessage {
          Section {
            AccessibleErrorLabel(message: errorMessage)
              .accessibilityIdentifier("account.emailChangeError")
          }
        }
      }
      .listRowBackground(theme.card)
    }
    .font(.karla(.body))
    .themedScrollBackground()
    .scrollEdgeEffectStyle(.hard, for: .top)
    .wrappingLargeTitle("Change email")
    .onDisappear {
      generation &+= 1
      sendTask?.cancel()
      sendTask = nil
      isSending = false
      email = ""
    }
  }

  private var normalizedEmail: String {
    email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private func send() {
    guard !isSending, connectionAvailable else { return }
    let newEmail = normalizedEmail
    guard newEmail.contains("@"), newEmail.contains(".") else {
      errorMessage = "Enter a valid email address."
      return
    }
    generation &+= 1
    let currentGeneration = generation
    isSending = true
    errorMessage = nil
    sendTask = Task {
      defer { if generation == currentGeneration { isSending = false } }
      do {
        try await appModel.requestEmailChange(email: newEmail, library: library)
        guard generation == currentGeneration, !Task.isCancelled else { return }
        confirmationEmail = newEmail
        AccessibilityNotification.Announcement("Confirmation email requested").post()
      } catch {
        guard generation == currentGeneration, !Task.isCancelled,
          error as? APIError != .cancelled else { return }
        errorMessage = error.userMessage(
          permission: "This account cannot request that email change.",
          fallback: "The confirmation could not be requested. Try again.")
      }
    }
  }
}
