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
  #if DEBUG
    @AppStorage(OverviewFixtureProtocol.sampleDataKey) private var useSampleData = false
  #endif

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
              size: 64,
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
          #if DEBUG
            // Hangs below the actions so Debug keeps the Release wordmark
            // position that the launch screen image is drawn for.
            .overlay(alignment: .bottom) {
              Button("Use sample data") { useSampleData = true }
                .accessibilityIdentifier("welcomeUseSampleData")
                .alignmentGuide(.bottom) { $0[.top] }
            }
          #endif
          .padding(.bottom, 16)
          .opacity(isRestoring ? 0 : 1)
          .allowsHitTesting(!isRestoring)
          .accessibilityHidden(isRestoring)
        }
      }
      .onAppear {
        withAnimation(.easeOut(duration: 0.4)) { coversBackground = false }
      }
      .toolbar(.hidden, for: .navigationBar)
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
