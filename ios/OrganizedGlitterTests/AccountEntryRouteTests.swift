import Foundation
import Testing
@testable import OrganizedGlitter

struct AccountEntryRouteTests {
  @Test
  func signedOutRoutesSurviveNavigationEncoding() throws {
    let path: [AccountEntryRoute] = [
      .methods,
      .emailSignIn,
      .emailRegister,
      .passwordReset(email: "user@example.test"),
      .verificationRequest(email: "user@example.test"),
    ]

    let data = try JSONEncoder().encode(path)
    let decoded = try JSONDecoder().decode([AccountEntryRoute].self, from: data)

    #expect(decoded == path)
  }
}
