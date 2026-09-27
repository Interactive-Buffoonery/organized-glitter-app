import AuthenticationServices
import SwiftUI

@MainActor
final class OAuthWebSession: NSObject, ASWebAuthenticationPresentationContextProviding {
  private let anchor: ASPresentationAnchor
  private var session: ASWebAuthenticationSession?
  private var continuation: CheckedContinuation<URL, Error>?
  private var started = false

  init(anchor: ASPresentationAnchor) {
    self.anchor = anchor
  }

  func start(_ url: URL, redirectURL: URL) async throws -> URL {
    guard !started, redirectURL.scheme == "https", let host = redirectURL.host else {
      throw OAuthError.presentationFailed
    }
    started = true
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        let session = ASWebAuthenticationSession(
          url: url,
          callback: .https(host: host, path: redirectURL.path)
        ) { [weak self] callback, error in
          Task { @MainActor in
            if let error = error as? ASWebAuthenticationSessionError,
              error.code == .canceledLogin {
              self?.finish(.failure(CancellationError()))
            } else if error != nil {
              self?.finish(.failure(OAuthError.presentationFailed))
            } else if let callback {
              self?.finish(.success(callback))
            } else {
              self?.finish(.failure(OAuthError.invalidResponse))
            }
          }
        }
        session.presentationContextProvider = self
        self.session = session
        if !session.start() { finish(.failure(OAuthError.presentationFailed)) }
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.cancel() }
    }
  }

  func cancel() {
    session?.cancel()
    finish(.failure(CancellationError()))
  }

  private func finish(_ result: Result<URL, Error>) {
    let continuation = continuation
    self.continuation = nil
    session = nil
    continuation?.resume(with: result)
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    anchor
  }
}

struct OAuthPresentationAnchor: UIViewRepresentable {
  let onWindow: @MainActor (UIWindow?) -> Void

  func makeUIView(context: Context) -> AnchorView {
    let view = AnchorView()
    view.onWindow = onWindow
    return view
  }

  func updateUIView(_ view: AnchorView, context: Context) {
    view.onWindow = onWindow
  }

  final class AnchorView: UIView {
    var onWindow: (@MainActor (UIWindow?) -> Void)?

    override func didMoveToWindow() {
      super.didMoveToWindow()
      let callback = onWindow
      DispatchQueue.main.async { [weak self] in
        guard let window = self?.window else { return }
        callback?(window)
      }
    }
  }
}
