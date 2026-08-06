import Foundation
import Testing
@testable import OrganizedGlitter

struct BackendContractTests {
  @Test
  func bundledContractIsComplete() throws {
    let contract = try BackendContract.bundled()

    #expect(contract.backendRepository == "Interactive-Buffoonery/organized-glitter")
    #expect(contract.backendCommit.count == 40)
    #expect(contract.schemaSha256.count == 64)
    #expect(!contract.pocketBaseVersion.isEmpty)
  }
}
