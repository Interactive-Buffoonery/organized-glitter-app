import SwiftUI

/// Signed-out navigation destinations. Owned by `WelcomeView` so method
/// switching can replace the current choice without stacking duplicates.
///
/// The stack uses `[AccountEntryRoute]` rather than `NavigationPath`. A
/// type-erased path is not `Codable`, and Xcode document versioning plus
/// in-process restoration crash when Continue with email pushes a second
/// destination.
enum AccountEntryRoute: Codable, Hashable {
  case methods
  case emailSignIn
  case emailRegister
  case passwordReset(email: String)
  case verificationRequest(email: String)
}
