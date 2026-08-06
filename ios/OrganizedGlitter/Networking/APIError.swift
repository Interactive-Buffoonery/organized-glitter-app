import Foundation

enum APIError: Error, Equatable {
  case unauthenticated
  case emailUnverified
  case forbidden
  case validation(String)
  case notFound
  case offline
  case server
  case decoding
  case cancelled

  static func from(statusCode: Int, body: Data) -> APIError {
    switch statusCode {
    case 400:
      let response = try? JSONDecoder().decode(PocketBaseErrorResponse.self, from: body)
      return .validation(response?.message ?? "Check the information and try again.")
    case 401:
      return .unauthenticated
    case 403:
      return .forbidden
    case 404:
      return .notFound
    default:
      return .server
    }
  }

  static func from(_ error: Error) -> APIError {
    if error is CancellationError {
      return .cancelled
    }

    guard let urlError = error as? URLError else {
      return .server
    }

    switch urlError.code {
    case .cancelled:
      return .cancelled
    case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost:
      return .offline
    default:
      return .server
    }
  }
}

private struct PocketBaseErrorResponse: Decodable {
  let message: String
}

extension Error {
  /// The two messages that were byte-identical across every screen. Everything
  /// else stayed local, because the wording is what makes it useful: "delete
  /// this note" and "delete this item" are not the same sentence to a reader.
  ///
  /// ponytail: `fallback` is a closure so callers keep their own default without
  /// this helper growing a case per screen.
  func userMessage(permission: String, fallback: @autoclosure () -> String) -> String {
    switch self as? APIError {
    case .unauthenticated:
      APIError.sessionExpiredMessage
    case .forbidden:
      permission
    case .validation(let message):
      message
    default:
      fallback()
    }
  }
}

extension APIError {
  static let sessionExpiredMessage = "Your session has expired. Sign in again."
  static let offlineMessage = "You’re offline. Reconnect and try again."
}
