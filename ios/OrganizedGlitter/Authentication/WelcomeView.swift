import SwiftUI

/// Signed-out home: Caveat wordmark with Create account and Sign in.
/// Account-entry screens stay free of authenticated tabs and app chrome.
struct WelcomeView: View {
  let model: AppModel

  var body: some View {
    AuthEntryContainer {
      VStack(spacing: 40) {
        Spacer(minLength: 24)
        BrandWordmark(size: 64)
          .frame(maxWidth: .infinity)
          .accessibilityIdentifier("welcomeWordmark")
        Spacer(minLength: 24)

        VStack(spacing: 12) {
          NavigationLink {
            RegistrationView(client: model.client)
          } label: {
            Text("Create account")
          }
          .buttonStyle(AuthPrimaryButtonStyle())
          .accessibilityIdentifier("welcomeCreateAccount")
          .disabled(model.client == nil)

          NavigationLink {
            SignInView(model: model)
          } label: {
            Text("Sign in")
          }
          .buttonStyle(AuthSecondaryButtonStyle())
          .accessibilityIdentifier("welcomeSignIn")
        }
        .padding(.bottom, 16)
      }
      .frame(minHeight: 520)
    }
    .toolbar(.hidden, for: .navigationBar)
  }
}
