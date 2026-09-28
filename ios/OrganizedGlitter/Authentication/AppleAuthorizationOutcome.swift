import AuthenticationServices
import Foundation

enum AppleAuthorizationOutcome {
  case authorized(state: String?, code: String?, name: AppleNativeName?)
  case cancelled
  case failed
  case invalidCredential

  init(_ result: Result<ASAuthorization, Error>) {
    switch result {
    case .failure(let error):
      self = (error as? ASAuthorizationError)?.code == .canceled ? .cancelled : .failed
    case .success(let authorization):
      guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
        self = .invalidCredential
        return
      }
      self = .authorized(
        state: credential.state,
        code: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
        name: AppleNativeName(fullName: credential.fullName)
      )
    }
  }
}
