import AuthenticationServices
import SwiftUI

struct AccountDeletionView: View {
  let appModel: AppModel
  let pendingCount: Int
  @State private var confirmsDeletion = false

  var body: some View {
    Form {
      Section {
        Text("Permanently delete your account, library records and uploaded files. This cannot be undone.")
        Text("Changes saved only on this device: \(pendingCount). These changes will also be removed after deletion is confirmed.")
          .accessibilityIdentifier("deletion.pendingEdits")
      }
      if let model = appModel.deletion {
        if model.isLocked {
          AccountDeletionStatusContent(appModel: appModel, model: model)
          if model.state == .uncertain || model.state == .verifying {
            AccountDeletionVerificationForm(model: model, recovery: true)
          }
        } else if model.state == .ready {
          Section {
            Text("Your identity is verified. Review the final confirmation to delete this account.")
              .accessibilityIdentifier("deletion.ready")
            Button("Review Account Deletion", role: .destructive) { confirmsDeletion = true }
              .accessibilityIdentifier("deletion.review")
          }
        } else {
          AccountDeletionVerificationForm(model: model, recovery: false)
        }
        if let error = model.errorMessage { Section { AccessibleErrorLabel(message: error) } }
      } else {
        Section {
          if case .signedIn(let user) = appModel.phase, user.verified == false {
            Text("Verify your email address before deleting this account. Your data remains available while you complete verification.")
          } else {
            ProgressView("Preparing account deletion")
            Text("Local data on this device is preserved. Contact support if this does not load.")
          }
          Link("Contact support", destination: AccountLinks.accountDeletionSupport)
        }
      }
    }
    .navigationTitle("Delete Account")
    .navigationBarTitleDisplayMode(.inline)
    .alert("Delete this account permanently?", isPresented: $confirmsDeletion) {
      Button("Delete Account Permanently", role: .destructive) {
        Task { await appModel.deletion?.confirm() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Your account, library records, uploaded files and \(pendingCount) changes saved only on this device will be removed. Vendor cleanup may continue after account deletion.")
    }
    .task {
      appModel.beginAccountDeletion()
      await appModel.deletion?.loadMethods()
    }
    .onChange(of: appModel.deletion?.state, initial: true) { _, state in
      if let message = AccountDeletionAccessibility.message(for: state) {
        AccessibilityNotification.Announcement(message).post()
      }
    }
    .onDisappear { appModel.deletion?.cancelPreparation() }
  }
}

struct AccountDeletionRecoveryView: View {
  let appModel: AppModel

  var body: some View {
    NavigationStack {
      Form {
        if let model = appModel.deletion {
          AccountDeletionStatusContent(appModel: appModel, model: model)
          if model.state == .uncertain || model.state == .verifying {
            AccountDeletionVerificationForm(model: model, recovery: true)
          }
          if let error = model.errorMessage { Section { AccessibleErrorLabel(message: error) } }
        } else {
          Section {
            Text("Secure deletion recovery could not be read. Account access remains locked and local data is preserved. Retry secure recovery or contact support for help.")
              .accessibilityIdentifier("deletion.secureRecoveryLocked")
            Button("Retry Secure Recovery", action: appModel.retrySessionRestoration)
            Link("Contact support", destination: AccountLinks.accountDeletionSupport)
          }
        }
      }
      .navigationTitle("Account Deletion")
      .task { await appModel.deletion?.loadMethods() }
      .onChange(of: appModel.deletion?.state, initial: true) { _, state in
        if let message = AccountDeletionAccessibility.message(for: state) {
          AccessibilityNotification.Announcement(message).post()
        }
      }
    }
  }
}

private struct AccountDeletionVerificationForm: View {
  let model: AccountDeletionModel
  let recovery: Bool
  @State private var password = ""
  @State private var anchor: UIWindow?
  @State private var browser: OAuthWebSession?
  @State private var authorizationTask: Task<Void, Never>?
  @State private var appleAttempt: (state: String, nonce: AppleSignInNonce)?
  @State private var active = false
  @State private var authError: String?
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Section(recovery ? "Verify again to continue" : "Verify your identity") {
      if recovery {
        Text("If the first request never reached the server, verify the original account again to continue with the same deletion request. Your local data stays locked until deletion is confirmed.")
      } else {
        Text("Available linked sign-in providers are shown below. Password verification may be tried if this account has a password. A different account cannot authorize deletion.")
      }
      if let methods = model.methods {
        if methods.passwordAvailable {
          Text("If this account has a password, you can try it here.")
          SecureField("Current password", text: $password)
            .textContentType(.password)
            .accessibilityIdentifier("deletion.password")
          Button("Verify Password") {
            let value = password
            password = ""
            authorizationTask = Task {
              if recovery { await model.reverifyPassword(value) }
              else { await model.verifyPassword(value) }
            }
          }
          .disabled(password.isEmpty || model.isBusy)
          .accessibilityIdentifier("deletion.verifyPassword")
        }
        if methods.appleAvailable {
          SignInWithAppleButton(.continue) { request in
            guard active, !model.isBusy else { return }
            do {
              let nonce = try AppleSignInNonce.generate()
              let state = UUID().uuidString
              appleAttempt = (state, nonce)
              request.nonce = nonce.digest
              request.state = state
            } catch { authError = "Apple verification could not start securely. Try again." }
          } onCompletion: { result in
            guard active, let attempt = appleAttempt else { return }
            appleAttempt = nil
            switch AppleAuthorizationOutcome(result) {
            case .authorized(let state, let code, _):
              guard state == attempt.state, let code, !code.isEmpty else {
                authError = "Apple did not provide a valid authorization. Try again."
                return
              }
              authorizationTask = Task {
                if recovery { await model.reverifyApple(code: code, nonce: attempt.nonce.raw) }
                else { await model.verifyApple(code: code, nonce: attempt.nonce.raw) }
              }
            case .cancelled: break
            default: authError = "Apple verification could not finish. Try again."
            }
          }
          .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
          .frame(minHeight: 50)
          .disabled(model.isBusy)
          .accessibilityLabel("Continue with Apple to verify this account")
        } else if methods.appleLinked {
          Text("Apple verification is unavailable now. Refresh verification methods or contact support if no other method works.")
        }
        ForEach(methods.socialProviders, id: \.self) { provider in
          Button("Verify with \(provider.displayName)") {
            guard let anchor else { return }
            let session = OAuthWebSession(anchor: anchor)
            browser = session
            authorizationTask = Task {
              if recovery {
                await model.reverifyOAuth(provider: provider,
                  present: { try await session.start($0, redirectURL: $1) })
              } else {
                await model.verifyOAuth(provider: provider,
                  present: { try await session.start($0, redirectURL: $1) })
              }
              browser = nil
            }
          }
          .disabled(model.isBusy || anchor == nil)
        }
        if !methods.appleAvailable && methods.socialProviders.isEmpty {
          Text(methods.passwordAvailable
            ? "No linked provider is available now. If this account has no password, contact support."
            : "No verification method is available now. Contact support for help.")
        }
        Button("Refresh Verification Methods") { Task { await model.loadMethods() } }
          .disabled(model.isBusy)
        Link("Contact support", destination: AccountLinks.accountDeletionSupport)
      } else if model.methodLoadFailed {
        Text("Sign-in methods could not be checked. Local data on this device is preserved.")
        Button("Retry Sign-In Methods") { Task { await model.loadMethods() } }
        Link("Contact support", destination: AccountLinks.accountDeletionSupport)
      } else {
        ProgressView("Checking connected sign-in methods")
      }
      if model.state == .verifying { ProgressView("Verifying identity") }
      if let authError { AccessibleErrorLabel(message: authError) }
    }
    .background(OAuthPresentationAnchor { anchor = $0 }.frame(width: 0, height: 0))
    .onAppear { active = true }
    .onDisappear {
      active = false
      appleAttempt = nil
      password = ""
      browser?.cancel()
      authorizationTask?.cancel()
    }
  }
}

private struct AccountDeletionStatusContent: View {
  let appModel: AppModel
  let model: AccountDeletionModel
  @State private var confirmsResubmission = false
  @AccessibilityFocusState private var statusFocused: Bool

  var body: some View {
    Section {
      switch model.state {
      case .completed(let cleanup):
        Text("Your account was deleted and its local data was removed.")
          .accessibilityIdentifier("deletion.completed")
          .accessibilityFocused($statusFocused)
        Text(cleanup == .pending ? "Vendor cleanup is pending." : "Vendor cleanup is completed.")
        Button("Done", action: appModel.finishAccountDeletion)
          .accessibilityIdentifier("deletion.done")
      case .localCleanupFailed:
        Text("Your account was deleted. Local cleanup is still pending.")
          .accessibilityFocused($statusFocused)
        Button("Retry Local Cleanup") { Task { await model.retry() } }
          .accessibilityIdentifier("deletion.retry")
      case .submitting:
        ProgressView("Confirming deletion and removing local data")
      case .verifying:
        ProgressView("Verifying original account")
      case .resubmissionReady:
        Text("The original account is verified again. Continue only if you still want to delete it.")
          .accessibilityIdentifier("deletion.resubmissionReady")
          .accessibilityFocused($statusFocused)
        Button("Continue Original Deletion", role: .destructive) { confirmsResubmission = true }
      default:
        Text("Deletion is not confirmed. Account access is locked and local data is preserved. Check the same request first. If it remains unresolved, verify the original account again or contact support.")
          .accessibilityIdentifier("deletion.uncertain")
          .accessibilityFocused($statusFocused)
        Button("Check Deletion Status") { Task { await model.retry() } }
          .accessibilityIdentifier("deletion.retry")
        Link("Contact support", destination: AccountLinks.accountDeletionSupport)
      }
    }
    .alert("Continue the original account deletion?", isPresented: $confirmsResubmission) {
      Button("Delete Original Account", role: .destructive) {
        Task { await model.confirmResubmission() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This uses the same deletion request and the original account session. Local data remains locked until the server confirms deletion.")
    }
    .onChange(of: model.state, initial: true) { _, state in
      switch state {
      case .resubmissionReady, .uncertain, .localCleanupFailed, .completed:
        statusFocused = true
      default: break
      }
    }
  }
}

private enum AccountDeletionAccessibility {
  static func message(for state: AccountDeletionModel.State?) -> String? {
    switch state {
    case .verifying: "Verifying the original account."
    case .ready: "Identity verified. Review the final deletion confirmation."
    case .resubmissionReady: "Original account verified again. Confirm whether to continue deletion."
    case .submitting: "Checking account deletion. Local data remains locked."
    case .uncertain: "Deletion is not confirmed. Account access remains locked."
    case .localCleanupFailed: "Account deleted. Local cleanup needs another attempt."
    case .completed: "Account deleted and local data removed."
    default: nil
    }
  }
}
