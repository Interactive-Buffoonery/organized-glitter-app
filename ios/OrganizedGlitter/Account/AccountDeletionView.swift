import AuthenticationServices
import SwiftUI

struct AccountDeletionView: View {
  let appModel: AppModel
  let pendingCount: Int
  @State private var password = ""
  @State private var confirmsDeletion = false
  @State private var anchor: UIWindow?
  @State private var browser: OAuthWebSession?
  @State private var authorizationTask: Task<Void, Never>?
  @State private var appleAttempt: (state: String, nonce: AppleSignInNonce)?
  @State private var active = false
  @State private var authError: String?
  @Environment(\.colorScheme) private var colorScheme

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
        } else if model.state == .ready {
          Section {
            Text("Your identity is verified. Review the final confirmation to delete this account.")
            Button("Review Account Deletion", role: .destructive) { confirmsDeletion = true }
              .accessibilityIdentifier("deletion.review")
          }
        } else {
          Section("Verify your identity") {
            Text("Use a sign-in method already connected to this verified account. A different account cannot authorize deletion.")
            SecureField("Current password", text: $password)
              .textContentType(.password)
              .accessibilityIdentifier("deletion.password")
            Button("Verify Password") {
              let value = password
              password = ""
              authorizationTask = Task { await model.verifyPassword(value) }
            }
            .disabled(password.isEmpty || model.isBusy)
            .accessibilityIdentifier("deletion.verifyPassword")
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
                authorizationTask = Task { await model.verifyApple(code: code, nonce: attempt.nonce.raw) }
              case .cancelled: break
              default: authError = "Apple verification could not finish. Try again."
              }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(minHeight: 50)
            .disabled(model.isBusy)
            .accessibilityLabel("Verify with connected Apple account")
            ForEach([SocialProvider.google, .discord], id: \.self) { provider in
              Button("Verify with \(provider.displayName)") {
                guard let anchor else { return }
                let session = OAuthWebSession(anchor: anchor)
                browser = session
                authorizationTask = Task {
                  await model.verifyOAuth(provider: provider, present: { try await session.start($0, redirectURL: $1) })
                  browser = nil
                }
              }
              .disabled(model.isBusy || anchor == nil)
            }
            if model.isBusy { ProgressView("Verifying identity") }
          }
        }
        if let error = model.errorMessage { Section { AccessibleErrorLabel(message: error) } }
      }
      if let authError { Section { AccessibleErrorLabel(message: authError) } }
    }
    .navigationTitle("Delete Account")
    .navigationBarTitleDisplayMode(.inline)
    .background(OAuthPresentationAnchor { anchor = $0 }.frame(width: 0, height: 0))
    .alert("Delete this account permanently?", isPresented: $confirmsDeletion) {
      Button("Delete Account Permanently", role: .destructive) {
        Task { await appModel.deletion?.confirm() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Your account, library records, uploaded files and \(pendingCount) changes saved only on this device will be removed. Vendor cleanup may continue after account deletion.")
    }
    .task {
      active = true
      appModel.beginAccountDeletion()
    }
    .onDisappear {
      active = false
      appleAttempt = nil
      password = ""
      browser?.cancel()
      authorizationTask?.cancel()
      appModel.deletion?.cancelPreparation()
    }
  }
}

struct AccountDeletionRecoveryView: View {
  let appModel: AppModel

  var body: some View {
    NavigationStack {
      Form {
        if let model = appModel.deletion {
          AccountDeletionStatusContent(appModel: appModel, model: model)
          if let error = model.errorMessage { Section { AccessibleErrorLabel(message: error) } }
        } else {
          Section {
            Text("Secure deletion recovery could not be read. Account access is locked and local data is preserved.")
            Button("Retry Secure Recovery", action: appModel.retrySessionRestoration)
          }
        }
      }
      .navigationTitle("Account Deletion")
    }
  }
}

private struct AccountDeletionStatusContent: View {
  let appModel: AppModel
  let model: AccountDeletionModel

  var body: some View {
    Section {
      switch model.state {
      case .completed(let cleanup):
        Text("Your account was deleted and its local data was removed.")
          .accessibilityIdentifier("deletion.completed")
        Text(cleanup == .pending ? "Vendor cleanup is pending." : "Vendor cleanup is completed.")
        Button("Done", action: appModel.finishAccountDeletion)
          .accessibilityIdentifier("deletion.done")
      case .localCleanupFailed:
        Text("Your account was deleted. Local cleanup is still pending.")
        Button("Retry Local Cleanup") { Task { await model.retry() } }
          .accessibilityIdentifier("deletion.retry")
      case .submitting:
        ProgressView("Confirming deletion and removing local data")
      default:
        Text("Deletion is not confirmed. Account access is locked and local data is preserved. Retry checks only the same request. If confirmation remains unavailable, contact support for recovery.")
        Button("Check Deletion Status") { Task { await model.retry() } }
          .accessibilityIdentifier("deletion.retry")
        Link("Contact support", destination: AccountLinks.accountDeletionSupport)
      }
    }
  }
}
