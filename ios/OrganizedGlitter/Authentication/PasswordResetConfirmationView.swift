import SwiftUI

struct PasswordResetConfirmationView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme

  let client: PocketBaseClient?
  let link: PasswordResetLink
  let onConfirmed: @MainActor () async -> Void

  @State private var password = ""
  @State private var passwordConfirmation = ""
  @State private var errorMessage: String?
  @State private var isSubmitting = false
  @State private var presentation: Presentation
  @State private var submitGeneration = 0
  @FocusState private var focusedField: Field?

  init(
    client: PocketBaseClient?,
    link: PasswordResetLink,
    onConfirmed: @escaping @MainActor () async -> Void
  ) {
    self.client = client
    self.link = link
    self.onConfirmed = onConfirmed
    _presentation = State(initialValue: link == .invalid ? .invalidLink : .form)
  }

  private enum Presentation: Equatable {
    case form
    case invalidLink
    case requestNewLink
    case complete
  }

  private enum Field {
    case password
    case confirmation
  }

  var body: some View {
    NavigationStack {
      Group {
        if presentation == .requestNewLink, let client {
          PasswordResetView(client: client, initialEmail: "")
        } else {
          AuthEntryContainer(alignment: .leading) {
            VStack(alignment: .leading, spacing: 24) {
              Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.foreground)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("passwordResetConfirmationTitle")

              content
            }
          }
        }
      }
      .navigationTitle("Password reset")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close", systemImage: "xmark") {
            dismiss()
          }
          .disabled(isSubmitting)
        }
      }
    }
    .interactiveDismissDisabled(isSubmitting)
    .onDisappear {
      submitGeneration += 1
      focusedField = nil
    }
  }

  private var title: String {
    switch presentation {
    case .form:
      "Create a new password"
    case .invalidLink:
      "This reset link can’t be used"
    case .requestNewLink:
      "Reset password"
    case .complete:
      "Password updated"
    }
  }

  @ViewBuilder
  private var content: some View {
    switch presentation {
    case .form:
      form
    case .invalidLink:
      recovery
    case .requestNewLink:
      EmptyView()
    case .complete:
      completion
    }
  }

  @ViewBuilder
  private var form: some View {
    Text("Use at least 8 characters with an uppercase letter, a lowercase letter, and a number.")
      .font(.body)
      .foregroundStyle(theme.mutedForeground)

    AuthLabeledField(title: "New password") {
      SecureField("New password", text: $password)
        .textContentType(.newPassword)
        .submitLabel(.next)
        .focused($focusedField, equals: .password)
        .onSubmit { focusedField = .confirmation }
        .accessibilityIdentifier("passwordResetNewPassword")
    }

    AuthLabeledField(title: "Confirm new password") {
      SecureField("Confirm new password", text: $passwordConfirmation)
        .textContentType(.newPassword)
        .submitLabel(.go)
        .focused($focusedField, equals: .confirmation)
        .onSubmit { Task { await confirm() } }
        .accessibilityIdentifier("passwordResetNewPasswordConfirmation")
    }

    if let errorMessage {
      AccessibleErrorLabel(message: errorMessage)
        .accessibilityIdentifier("passwordResetConfirmationError")
    }

    Button {
      Task { await confirm() }
    } label: {
      if isSubmitting {
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 52)
      } else {
        Text("Reset password")
      }
    }
    .buttonStyle(AuthPrimaryButtonStyle())
    .disabled(isSubmitting || password.isEmpty || passwordConfirmation.isEmpty)
    .accessibilityIdentifier("passwordResetConfirm")
  }

  @ViewBuilder
  private var recovery: some View {
    Text("The link may have expired or already been used. Request a new link and try again.")
      .font(.body)
      .foregroundStyle(theme.foreground)
      .accessibilityIdentifier("passwordResetInvalidLink")

    Button("Request a new reset link") {
      presentation = .requestNewLink
    }
    .buttonStyle(AuthPrimaryButtonStyle())
    .disabled(client == nil)
    .accessibilityIdentifier("passwordResetRequestNewLink")
  }

  @ViewBuilder
  private var completion: some View {
    Label(
      "Your password has been reset. Sign in with your new password.",
      systemImage: "checkmark.circle.fill"
    )
    .font(.body)
    .foregroundStyle(theme.foreground)
    .accessibilityIdentifier("passwordResetComplete")

    Button("Continue to sign in") {
      dismiss()
    }
    .buttonStyle(AuthPrimaryButtonStyle())
    .accessibilityIdentifier("passwordResetContinue")
  }

  private func confirm() async {
    guard let client else {
      errorMessage = "Organized Glitter is not configured for password reset."
      return
    }
    guard case .confirmation(let token) = link else {
      presentation = .invalidLink
      return
    }
    if let validationMessage = PasswordResetFormValidator.message(
      password: password,
      confirmation: passwordConfirmation
    ) {
      errorMessage = validationMessage
      return
    }

    submitGeneration += 1
    let generation = submitGeneration
    isSubmitting = true
    errorMessage = nil
    defer {
      if generation == submitGeneration {
        isSubmitting = false
      }
    }

    do {
      try await client.confirmPasswordReset(
        token: token,
        password: password,
        passwordConfirmation: passwordConfirmation
      )
      guard generation == submitGeneration else { return }
      password = ""
      passwordConfirmation = ""
      await onConfirmed()
      guard generation == submitGeneration else { return }
      presentation = .complete
    } catch let error as APIError {
      guard generation == submitGeneration else { return }
      switch error {
      case .cancelled:
        return
      case .validation, .notFound, .unauthenticated, .forbidden:
        password = ""
        passwordConfirmation = ""
        presentation = .invalidLink
      case .offline:
        errorMessage = "You appear to be offline. Reconnect and try again."
      case .server, .decoding, .emailUnverified:
        errorMessage = "Your password could not be reset. Try again."
      }
    } catch {
      guard generation == submitGeneration else { return }
      errorMessage = "Your password could not be reset. Try again."
    }
  }
}
