import SwiftUI

/// Signed-out home: Caveat wordmark with Create account and Sign in.
/// Account-entry screens stay free of authenticated tabs and app chrome.
///
/// Also the restoring splash: while `phase == .restoring` the sparkles
/// twinkle, the actions stay hidden but keep their space, and the themed
/// background fades in over the flat launch color. The wordmark sits where
/// the launch screen image drew it, so nothing moves between the two.
struct WelcomeView: View {
  let model: AppModel

  @State private var path: [AccountEntryRoute] = []
  @State private var coversBackground: Bool
  @State private var methodMode: AccountMethodView.Mode = .signIn
  @State private var confirmsLocalRemoval = false

  init(model: AppModel) {
    self.model = model
    _coversBackground = State(initialValue: model.phase == .restoring)
  }

  private var isRestoring: Bool { model.phase == .restoring }

  var body: some View {
    NavigationStack(path: $path) {
      AuthEntryContainer(fillsHeight: true, coversBackground: coversBackground) {
        VStack(spacing: 0) {
          VStack {
            Spacer(minLength: 0)
            BrandWordmark(
              size: AccountEntryLayout.welcomeWordmarkSize,
              sparkles: isRestoring ? .twinkling : .still,
              accessibilityIdentifier: "welcomeWordmark"
            )
            .accessibilityRepresentation {
              VStack {
                Text("Organized Glitter")
                  .accessibilityAddTraits(.isHeader)
                  .accessibilityIdentifier("welcomeWordmark")
                if isRestoring {
                  Text("Opening your library")
                    .accessibilityIdentifier("launchProgress")
                }
              }
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
          }

          VStack(spacing: AccountEntryLayout.actionSpacing) {
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
          .safeAreaInset(edge: .bottom) {
            if !isRestoring, model.removableLocalScopeCount > 0 {
              Button("Remove Saved Libraries From This Device", role: .destructive) {
                confirmsLocalRemoval = true
              }
              .font(.footnote)
              .accessibilityIdentifier("session.removeLocalData")
            }
          }
          .padding(.bottom, AccountEntryLayout.actionsBottomPadding)
          .opacity(isRestoring ? 0 : 1)
          .allowsHitTesting(!isRestoring)
          .accessibilityHidden(isRestoring)
        }
      }
      .onAppear {
        withAnimation(.easeOut(duration: 0.4)) { coversBackground = false }
      }
      .toolbar(.hidden, for: .navigationBar)
      .task(id: model.phase) { await model.loadRemovableLocalScopes() }
      .alert("Remove saved libraries from this device?", isPresented: $confirmsLocalRemoval) {
        Button("Remove Saved Libraries", role: .destructive) {
          Task { await model.removeSavedLibrariesFromDevice() }
        }
        Button("Keep Saved Libraries", role: .cancel) {}
      } message: {
        Text("This removes \(model.removableLocalScopeCount) saved \(model.removableLocalScopeCount == 1 ? "library" : "libraries") and all unsynced changes for this server on this device. It does not delete a server account or confirm whether any account was deleted. Sign in again to recover access instead.")
      }
      .navigationDestination(for: AccountEntryRoute.self) { route in
        switch route {
        case .methods:
          AccountMethodView(model: model, mode: $methodMode)
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
