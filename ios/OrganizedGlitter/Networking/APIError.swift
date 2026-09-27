import Foundation

enum APIError: Error, Equatable {
  case unauthenticated
  case emailUnverified
  case forbidden
  case conflict
  case validation(String)
  case notFound
  case offline
  case server
  case decoding
  case cancelled

  static func from(
    statusCode: Int, body: Data, isPasswordAuthentication: Bool = false
  ) -> APIError {
    switch statusCode {
    case 400:
      let response = try? JSONDecoder().decode(PocketBaseErrorResponse.self, from: body)
      return .validation(response?.message ?? "Check the information and try again.")
    case 401:
      return .unauthenticated
    case 403:
      if isPasswordAuthentication,
        let response = try? JSONDecoder().decode(PocketBaseErrorResponse.self, from: body),
        response.message
          == "The request doesn't satisfy the collection requirements to authenticate."
      {
        return .emailUnverified
      }
      return .forbidden
    case 409:
      return .conflict
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
  func userMessage(
    permission: String,
    offline: String = APIError.offlineMessage,
    fallback: @autoclosure () -> String
  ) -> String {
    if let error = self as? LibrarySessionError, let message = error.errorDescription {
      return message
    }
    switch self as? APIError {
    case .unauthenticated:
      return APIError.sessionExpiredMessage
    case .forbidden:
      return permission
    case .validation(let message):
      return message
    case .offline:
      return offline
    default:
      return fallback()
    }
  }
}

extension APIError {
  static let sessionExpiredMessage = "Your session has expired. Sign in again."
  static let offlineMessage = "You’re offline. Reconnect and try again."

  static func needsConnection(_ action: String) -> String {
    "\(action) needs a connection. Reconnect and try again."
  }
}
