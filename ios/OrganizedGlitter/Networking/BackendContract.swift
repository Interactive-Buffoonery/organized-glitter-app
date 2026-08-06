import Foundation

struct BackendContract: Decodable, Equatable, Sendable {
  let backendRepository: String
  let backendCommit: String
  let pocketBaseVersion: String
  let schemaSha256: String

  static func bundled(in bundle: Bundle = .main) throws -> BackendContract {
    guard let url = bundle.url(forResource: "BackendContract", withExtension: "json") else {
      throw BackendContractError.missing
    }

    return try JSONDecoder().decode(
      BackendContract.self,
      from: Data(contentsOf: url)
    )
  }
}

enum BackendContractError: Error {
  case missing
}
