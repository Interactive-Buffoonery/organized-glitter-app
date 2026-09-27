import Foundation
import Testing

@testable import OrganizedGlitter

struct PasswordResetLinkTests {
  @Test
  func parsesCanonicalOpaqueTokenExactlyOnce() throws {
    let url = try #require(
      URL(string: "https://organizedglitter.app/auth/confirm-password-reset/part.one%252Ftwo")
    )

    #expect(PasswordResetLink.parse(url) == .confirmation(token: "part.one%2Ftwo"))
  }

  @Test
  func marksCanonicalRoutesWithoutOneTokenSegmentInvalid() throws {
    let missing = try #require(
      URL(string: "https://organizedglitter.app/auth/confirm-password-reset/")
    )
    let extra = try #require(
      URL(string: "https://organizedglitter.app/auth/confirm-password-reset/token/extra")
    )

    #expect(PasswordResetLink.parse(missing) == .invalid)
    #expect(PasswordResetLink.parse(extra) == .invalid)
  }

  @Test
  func ignoresURLsOutsideCanonicalHTTPSRoute() throws {
    let http = try #require(
      URL(string: "http://organizedglitter.app/auth/confirm-password-reset/token")
    )
    let otherHost = try #require(
      URL(string: "https://example.test/auth/confirm-password-reset/token")
    )
    let legacy = try #require(
      URL(string: "https://organizedglitter.app/reset-password?token=token")
    )

    #expect(PasswordResetLink.parse(http) == nil)
    #expect(PasswordResetLink.parse(otherHost) == nil)
    #expect(PasswordResetLink.parse(legacy) == nil)
  }

  @Test
  func validatesNewPasswordForm() {
    let cases = [
      ("short1A", "short1A", "Use at least 8 characters for your password."),
      ("lowercase1", "lowercase1", "Add at least one uppercase letter."),
      ("UPPERCASE1", "UPPERCASE1", "Add at least one lowercase letter."),
      ("NoNumberHere", "NoNumberHere", "Add at least one number."),
      ("ValidPass1", "Different1", "Passwords do not match."),
    ]

    for (password, confirmation, message) in cases {
      #expect(
        PasswordResetFormValidator.message(password: password, confirmation: confirmation)
          == message
      )
    }
  }

  @Test
  func acceptsMatchingPasswordThatMeetsSharedRules() {
    #expect(
      PasswordResetFormValidator.message(
        password: "ValidPass1",
        confirmation: "ValidPass1"
      ) == nil
    )
  }
}
