import Foundation

struct OAuthProvider: Decodable, Sendable {
  let name: String
  let authURL: String
  let codeVerifier: String
  let state: String

  func authorizationURL(redirectURL: URL) throws -> URL {
    guard !state.isEmpty, !codeVerifier.isEmpty,
      redirectURL.scheme == "https",
      var components = URLComponents(string: authURL),
      components.scheme == "https",
      components.host != nil,
      let items = components.queryItems,
      items.filter({ $0.name == "redirect_uri" }).count == 1
    else { throw OAuthError.invalidResponse }
    components.queryItems = items.filter { $0.name != "state" && $0.name != "redirect_uri" } + [
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
    ]
    guard let url = components.url else { throw OAuthError.invalidResponse }
    return url
  }

  func authorizationCode(from callback: URL, redirectURL: URL) throws -> String {
    guard callback.scheme == "https",
      callback.host == redirectURL.host,
      callback.port == redirectURL.port,
      callback.path == redirectURL.path,
      callback.user == nil, callback.password == nil, callback.fragment == nil,
      let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems
    else { throw OAuthError.invalidResponse }
    let states = items.filter { $0.name == "state" }
    let errors = items.filter { $0.name == "error" }
    guard !state.isEmpty, states.count == 1, states[0].value == state, errors.count <= 1 else {
      throw OAuthError.invalidResponse
    }
    guard errors.isEmpty else { throw OAuthError.denied }
    let codes = items.filter { $0.name == "code" }
    guard codes.count == 1, let code = codes[0].value, !code.isEmpty else {
      throw OAuthError.invalidResponse
    }
    return code
  }
}

enum OAuthError: Error, Equatable {
  case unavailable
  case invalidResponse
  case denied
  case presentationFailed
}
