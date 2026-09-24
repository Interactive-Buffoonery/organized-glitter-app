import Foundation
import Testing

@testable import OrganizedGlitter

@MainActor
struct ProtectedFileAccessTests {
  @Test
  func renewsBeforeTokenExpiry() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let claims = Data(#"{"exp":1120}"#.utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "=", with: "")
    let token = "header.\(claims).signature"
    #expect(ProtectedFileAccess.renewalDelay(for: token, now: now) == 60)

    let shortClaims = Data(#"{"exp":1020}"#.utf8).base64EncodedString()
    #expect(
      ProtectedFileAccess.renewalDelay(for: "header.\(shortClaims).signature", now: now) == 1)
    #expect(ProtectedFileAccess.renewalDelay(for: "invalid", now: now) == 30)
  }
}
