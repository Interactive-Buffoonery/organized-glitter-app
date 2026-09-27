import AuthenticationServices
import SwiftUI

@MainActor
final class OAuthWebSession: NSObject, ASWebAuthenticationPresentationContextProviding {
  private let anchor: ASPresentationAnchor
  private let onCancel: @MainActor () -> Void
  private var session: ASWebAuthenticationSession?
  private var accepted = false

  init(anchor: ASPresentationAnchor, onCancel: @escaping @MainActor () -> Void) {
    self.anchor = anchor
    self.onCancel = onCancel
  }

  func start(_ url: URL) throws {
    let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { [weak self] _, _ in
      Task { @MainActor in
        guard let self, !self.accepted else { return }
        self.session = nil
        self.onCancel()
      }
    }
    session.presentationContextProvider = self
    self.session = session
    guard session.start() else {
      self.session = nil
      throw OAuthError.presentationFailed
    }
  }

  func dismissAccepted() {
    accepted = true
    session?.cancel()
    session = nil
  }

  func cancel() {
    accepted = true
    session?.cancel()
    session = nil
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
      let window = window
      DispatchQueue.main.async { [weak self] in
        self?.onWindow?(window)
      }
    }
  }
}
