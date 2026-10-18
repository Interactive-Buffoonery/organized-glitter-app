import SwiftUI

struct ChangePasswordView: View {
  @Environment(\.connectionAvailable) private var connectionAvailable
  let appModel: AppModel
  let library: LibrarySession
  let client: PocketBaseClient
  let currentEmail: String

  @State private var currentPassword = ""
  @State private var password = ""
  @State private var confirmation = ""
  @State private var isSaving = false
  @State private var didChange = false
  @State private var errorMessage: String?
  @State private var outcomeUnknown = false
  @State private var generation = 0

  var body: some View {
    Form {
      if didChange {
        Section {
          Label("Password changed", systemImage: "checkmark.circle")
            .accessibilityIdentifier("account.passwordChanged")
        }
      } else {
        Section("Password") {
          SecureField("Current password", text: $currentPassword)
            .textContentType(.password)
            .accessibilityIdentifier("account.currentPassword")
          SecureField("New password", text: $password)
            .textContentType(.newPassword)
            .accessibilityIdentifier("account.newPassword")
          SecureField("Confirm new password", text: $confirmation)
            .textContentType(.newPassword)
            .accessibilityIdentifier("account.confirmPassword")
          if !password.isEmpty, let validationMessage {
            Text(validationMessage).fixedSize(horizontal: false, vertical: true)
          }
          Button("Change password", action: save)
            .disabled(isSaving || !connectionAvailable || currentPassword.isEmpty
              || validationMessage != nil || appModel.isSigningOut
              || appModel.isChangingPassword || outcomeUnknown)
            .accessibilityIdentifier("account.savePassword")
          if isSaving { ProgressView("Changing password") }
        }
        .disabled(isSaving)
      }
      Section {
        Text("Use your current password. If you usually sign in with Apple, Google, or Discord and don't know a password, reset it first.")
          .fixedSize(horizontal: false, vertical: true)
        NavigationLink("Reset password") {
          PasswordResetView(client: client, initialEmail: currentEmail)
        }
        .disabled(isSaving)
      }
      if !connectionAvailable { Section { NeedsConnectionHint() } }
      if let errorMessage {
        Section {
          AccessibleErrorLabel(message: errorMessage)
            .accessibilityIdentifier("account.passwordChangeError")
        }
      }
    }
    .font(.karla(.body))
    .themedScrollBackground()
    .navigationTitle("Change password")
    .onDisappear {
      generation &+= 1
      isSaving = false
      clearPasswords()
    }
  }

  private var validationMessage: String? {
    PasswordResetFormValidator.message(password: password, confirmation: confirmation)
  }

  private func clearPasswords() {
    currentPassword = ""
    password = ""
    confirmation = ""
  }

  private func save() {
    guard !isSaving, connectionAvailable, !currentPassword.isEmpty,
      validationMessage == nil else { return }
    generation &+= 1
    let currentGeneration = generation
    isSaving = true
    errorMessage = nil
    // A dispatched change finishes after the form closes so session recovery still runs.
    Task {
      defer { if generation == currentGeneration { isSaving = false } }
      do {
        _ = try await appModel.changePassword(
          oldPassword: currentPassword, password: password, confirmation: confirmation,
          library: library, onAccepted: {
            clearPasswords()
            AccessibilityNotification.Announcement("Password changed").post()
          })
        guard generation == currentGeneration, !Task.isCancelled else { return }
        didChange = true
      } catch {
        guard generation == currentGeneration, !Task.isCancelled,
          error as? APIError != .cancelled else { return }
        currentPassword = ""
        if error as? APIError == .offline || error as? APIError == .server {
          outcomeUnknown = true
          errorMessage = "The result could not be confirmed. Sign in again with your new password or reset it before trying another change. Your unsent library changes stay on this device."
          return
        }
        errorMessage = error.userMessage(
          permission: "This account cannot change its password.",
          fallback: "The password could not be changed. Check your current password and try again.")
      }
    }
  }
}
