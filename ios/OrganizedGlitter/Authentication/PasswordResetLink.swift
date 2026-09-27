import Foundation

enum PasswordResetLink: Equatable {
  case confirmation(token: String)
  case invalid

  static func parse(_ url: URL) -> PasswordResetLink? {
    guard
      url.scheme?.lowercased() == "https",
      url.host?.lowercased() == "organizedglitter.app",
      url.port == nil,
      url.user == nil,
      url.password == nil,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else {
      return nil
    }

    let segments = components.percentEncodedPath.split(
      separator: "/", omittingEmptySubsequences: false)
    guard
      segments.count >= 3,
      segments.prefix(3).elementsEqual(["", "auth", "confirm-password-reset"])
    else {
      return nil
    }
    guard
      segments.count == 4,
      !segments[3].isEmpty,
      let token = String(segments[3]).removingPercentEncoding,
      !token.isEmpty
    else {
      return .invalid
    }

    return .confirmation(token: token)
  }
}

struct PasswordResetDestination: Identifiable, Equatable {
  let id = UUID()
  let link: PasswordResetLink
}

enum PasswordResetFormValidator {
  static func message(password: String, confirmation: String) -> String? {
    guard password.count >= 8 else {
      return "Use at least 8 characters for your password."
    }
    guard password.range(of: "[A-Z]", options: .regularExpression) != nil else {
      return "Add at least one uppercase letter."
    }
    guard password.range(of: "[a-z]", options: .regularExpression) != nil else {
      return "Add at least one lowercase letter."
    }
    guard password.range(of: #"\d"#, options: .regularExpression) != nil else {
      return "Add at least one number."
    }
    guard password == confirmation else {
      return "Passwords do not match."
    }
    return nil
  }
}
