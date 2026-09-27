import SwiftUI

struct PasswordResetConfirmationView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme

  let client: PocketBaseClient?
  let link: PasswordResetLink
  let clearSession: @MainActor () async -> Void

  @State private var password = ""
  @State private var passwordConfirmation = ""
  @State private var errorMessage: String?
  @State private var isSubmitting = false
  @State private var presentation: Presentation
  @State private var submitGeneration = 0
  @State private var confirmationTask: Task<Void, Never>?
  @FocusState private var focusedField: Field?
  @AccessibilityFocusState private var isOutcomeFocused: Bool

  init(
    client: PocketBaseClient?,
    link: PasswordResetLink,
    clearSession: @escaping @MainActor () async -> Void
  ) {
    self.client = client
    self.link = link
    self.clearSession = clearSession
    _presentation = State(initialValue: link == .invalid ? .invalidLink : .form)
  }

  private enum Presentation: Equatable {
    case form
    case invalidLink
    case requestNewLink
    case complete
    case outcomeUnknown
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
    .onAppear {
      if presentation == .invalidLink {
        announceInvalidLink()
      }
    }
    .onDisappear {
      confirmationTask?.cancel()
      confirmationTask = nil
      submitGeneration += 1
      focusedField = nil
    }
  }

  private var title: String {
    switch presentation {
    case .form:
      "Create a new password"
    case .invalidLink:
      "Request a new reset link"
    case .requestNewLink:
      "Reset password"
    case .complete:
      "Password updated"
    case .outcomeUnknown:
      "Check your password reset"
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
    case .outcomeUnknown:
      uncertainOutcome
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
        .onSubmit(startConfirmation)
        .accessibilityIdentifier("passwordResetNewPasswordConfirmation")
    }

    if let errorMessage {
      AccessibleErrorLabel(message: errorMessage)
        .accessibilityIdentifier("passwordResetConfirmationError")
    }

    Button {
      startConfirmation()
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
    Text("This link has expired, has already been used, or is invalid. Request a new reset email to choose a password.")
      .font(.body)
      .foregroundStyle(theme.foreground)
      .accessibilityFocused($isOutcomeFocused)
      .accessibilityIdentifier("passwordResetInvalidLink")

    Button("Send a new reset link") {
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
    .accessibilityFocused($isOutcomeFocused)
    .accessibilityIdentifier("passwordResetComplete")

    Button("Continue to sign in") {
      dismiss()
    }
    .buttonStyle(AuthPrimaryButtonStyle())
    .accessibilityIdentifier("passwordResetContinue")
  }

  @ViewBuilder
  private var uncertainOutcome: some View {
    Text("We couldn’t confirm whether your password was reset. Try signing in with your new password. If it doesn’t work, request a new reset link.")
      .font(.body)
      .foregroundStyle(theme.foreground)
      .accessibilityFocused($isOutcomeFocused)
      .accessibilityIdentifier("passwordResetOutcomeUnknown")

    Button("Try signing in") {
      dismiss()
    }
    .buttonStyle(AuthPrimaryButtonStyle())
    .accessibilityIdentifier("passwordResetTrySignIn")

    Button("Send a new reset link") {
      presentation = .requestNewLink
    }
    .buttonStyle(AuthLinkButtonStyle())
    .disabled(client == nil)
    .accessibilityIdentifier("passwordResetRequestNewLink")
  }

  private func startConfirmation() {
    guard confirmationTask == nil else { return }
    submitGeneration += 1
    let generation = submitGeneration
    confirmationTask = Task {
      await confirm(generation: generation)
      if generation == submitGeneration {
        confirmationTask = nil
      }
    }
  }

  private func confirm(generation: Int) async {
    guard let client else {
      errorMessage = "Organized Glitter is not configured for password reset."
      return
    }
    guard case .confirmation(let token) = link else {
      presentation = .invalidLink
      announceInvalidLink()
      return
    }
    if let validationMessage = PasswordResetFormValidator.message(
      password: password,
      confirmation: passwordConfirmation
    ) {
      errorMessage = validationMessage
      return
    }

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
      await clearSession()
      guard generation == submitGeneration else { return }
      presentation = .complete
      isOutcomeFocused = true
      AccessibilityNotification.Announcement(
        "Password updated. Your password has been reset. Sign in with your new password."
      ).post()
    } catch let error as APIError {
      guard generation == submitGeneration else { return }
      switch error {
      case .cancelled:
        return
      case .validation, .notFound, .unauthenticated, .forbidden:
        password = ""
        passwordConfirmation = ""
        presentation = .invalidLink
        announceInvalidLink()
      case .offline:
        await showUncertainOutcome(generation: generation)
      case .server, .decoding, .emailUnverified:
        await showUncertainOutcome(generation: generation)
      }
    } catch {
      guard generation == submitGeneration else { return }
      await showUncertainOutcome(generation: generation)
    }
  }

  private func showUncertainOutcome(generation: Int) async {
    password = ""
    passwordConfirmation = ""
    await clearSession()
    guard generation == submitGeneration else { return }
    presentation = .outcomeUnknown
    isOutcomeFocused = true
    AccessibilityNotification.Announcement(
      "We couldn’t confirm whether your password was reset. Try signing in with your new password."
    ).post()
  }

  private func announceInvalidLink() {
    isOutcomeFocused = true
    AccessibilityNotification.Announcement(
      "This reset link can’t be used. Request a new reset email using the Send a new reset link button."
    ).post()
  }
}
