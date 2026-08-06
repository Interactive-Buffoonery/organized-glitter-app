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
}
