import SwiftUI

/// Signed-out navigation destinations. Owned by `WelcomeView` so method
/// switching can replace the current choice without stacking duplicates.
enum AccountEntryRoute: Hashable {
  case methods
  case emailSignIn
  case emailRegister
}
