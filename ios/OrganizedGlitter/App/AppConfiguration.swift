import Foundation

struct AppConfiguration: Sendable {
  let pocketBaseURL: URL

  static func load(bundle: Bundle = .main) throws -> AppConfiguration {
    guard
      let value = bundle.object(forInfoDictionaryKey: "PocketBaseBaseURL") as? String,
      let url = URL(string: value),
      let scheme = url.scheme,
      ["http", "https"].contains(scheme)
    else {
      throw AppConfigurationError.invalidPocketBaseURL
    }

    return AppConfiguration(pocketBaseURL: url)
  }
}

enum AppConfigurationError: LocalizedError {
  case invalidPocketBaseURL

  var errorDescription: String? {
    "Organized Glitter is missing a valid PocketBase server URL."
  }
}
