import SwiftUI

/// Signed-out home: Caveat wordmark with Create account and Sign in.
/// Account-entry screens stay free of authenticated tabs and app chrome.
struct WelcomeView: View {
  let model: AppModel

  @State private var path = NavigationPath()

  var body: some View {
    NavigationStack(path: $path) {
      AuthEntryContainer(fillsHeight: true) {
        VStack(spacing: 40) {
          Spacer(minLength: 24)
          BrandWordmark(size: 64)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("welcomeWordmark")
          Spacer(minLength: 24)

          VStack(spacing: 12) {
            Button {
              path.append(AccountEntryRoute.methods(.register))
            } label: {
              Text("Create account")
            }
            .buttonStyle(AuthPrimaryButtonStyle())
            .accessibilityIdentifier("welcomeCreateAccount")
            .disabled(model.client == nil)

            Button {
              path.append(AccountEntryRoute.methods(.signIn))
            } label: {
              Text("Sign in")
            }
            .buttonStyle(AuthSecondaryButtonStyle())
            .accessibilityIdentifier("welcomeSignIn")
          }
          .padding(.bottom, 16)
        }
      }
      .toolbar(.hidden, for: .navigationBar)
      .navigationDestination(for: AccountEntryRoute.self) { route in
        switch route {
        case .methods(let mode):
          AccountMethodView(model: model, mode: mode, path: $path)
        case .emailSignIn:
          SignInView(model: model)
        case .emailRegister:
          RegistrationView(client: model.client, path: $path)
        }
      }
    }
  }
}
