import SwiftUI

/// Signed-out home: Caveat wordmark with Create account and Sign in.
/// Account-entry screens stay free of authenticated tabs and app chrome.
struct WelcomeView: View {
  let model: AppModel

  @State private var path = NavigationPath()
  @State private var methodMode: AccountMethodView.Mode = .signIn

  var body: some View {
    NavigationStack(path: $path) {
      AuthEntryContainer(fillsHeight: true) {
        VStack(spacing: 0) {
          VStack {
            Spacer(minLength: 0)
            BrandWordmark(size: 64, accessibilityIdentifier: "welcomeWordmark")
              .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
          }

          VStack(spacing: 12) {
            Button {
              methodMode = .register
              path.append(AccountEntryRoute.methods)
            } label: {
              Text("Create account")
            }
            .buttonStyle(AuthPrimaryButtonStyle())
            .accessibilityIdentifier("welcomeCreateAccount")
            .disabled(model.client == nil)

            Button {
              methodMode = .signIn
              path.append(AccountEntryRoute.methods)
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
        case .methods:
          AccountMethodView(model: model, mode: $methodMode, path: $path)
        case .emailSignIn:
          SignInView(model: model, path: $path)
        case .emailRegister:
          RegistrationView(client: model.client, path: $path, methodMode: $methodMode)
        case .passwordReset(let email):
          if let client = model.client {
            PasswordResetView(client: client, initialEmail: email)
          } else {
            Text("Organized Glitter is not configured for password reset.")
              .padding()
          }
        case .verificationRequest(let email):
          if let client = model.client {
            VerificationRequestView(client: client, initialEmail: email)
          } else {
            Text("Organized Glitter is not configured for verification.")
              .padding()
          }
        }
      }
    }
  }
}
