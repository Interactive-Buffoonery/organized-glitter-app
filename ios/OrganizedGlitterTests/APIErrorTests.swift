import Foundation
import Testing
@testable import OrganizedGlitter

struct APIErrorTests {
  @Test
  func mapsPocketBaseRuleResponses() {
    #expect(APIError.from(statusCode: 401, body: Data()) == .unauthenticated)
    #expect(APIError.from(statusCode: 403, body: Data()) == .forbidden)
    #expect(APIError.from(statusCode: 404, body: Data()) == .notFound)
    #expect(APIError.from(statusCode: 500, body: Data()) == .server)
  }

  @Test
  func mapsOfflineErrors() {
    let error = URLError(.notConnectedToInternet)
    #expect(APIError.from(error) == .offline)
    #expect(APIError.from(URLError(.cancelled)) == .cancelled)
  }

  @Test
  func onlineOnlyErrorsExplainWhichActionNeedsConnection() {
    let message = APIError.offline.userMessage(
      permission: "No permission",
      offline: APIError.needsConnection("Adding a progress note"),
      fallback: "Unknown error")
    #expect(message == "Adding a progress note needs a connection. Reconnect and try again.")
    #expect(LibrarySessionError.pendingChanges.userMessage(
      permission: "No permission", fallback: "Unknown error")
      == "Synchronize or resolve this item's pending changes before continuing.")
    #expect(APIError.forbidden.userMessage(
      permission: "No permission", fallback: "Unknown error") == "No permission")
    #expect(APIError.server.userMessage(
      permission: "No permission", fallback: "Unknown error") == "Unknown error")
  }
}
