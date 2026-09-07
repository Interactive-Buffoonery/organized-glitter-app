import SwiftUI

/// Signed-out home: Caveat wordmark with Create account and Sign in.
/// Account-entry screens stay free of authenticated tabs and app chrome.
struct WelcomeView: View {
  let model: AppModel

  var body: some View {
    AuthEntryContainer(fillsHeight: true) {
      VStack(spacing: 40) {
        Spacer(minLength: 24)
        BrandWordmark(size: 64)
          .frame(maxWidth: .infinity)
          .accessibilityIdentifier("welcomeWordmark")
        Spacer(minLength: 24)

        VStack(spacing: 12) {
          NavigationLink {
            AccountMethodView(model: model, mode: .register)
          } label: {
            Text("Create account")
          }
          .buttonStyle(AuthPrimaryButtonStyle())
          .accessibilityIdentifier("welcomeCreateAccount")
          .disabled(model.client == nil)

          NavigationLink {
            AccountMethodView(model: model, mode: .signIn)
          } label: {
            Text("Sign in")
          }
          .buttonStyle(AuthSecondaryButtonStyle())
          .accessibilityIdentifier("welcomeSignIn")
        }
        .padding(.bottom, 8)
      }
    }
    .toolbar(.hidden, for: .navigationBar)
  }
}
