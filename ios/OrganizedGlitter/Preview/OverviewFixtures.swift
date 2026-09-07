#if DEBUG
  import Foundation
  import UIKit

  /// Isolated, fictional responses for Overview runtime review. Never contacts a server.
  final class OverviewFixtureProtocol: URLProtocol, @unchecked Sendable {
    static var scenario: String? {
      let arguments = ProcessInfo.processInfo.arguments
      guard let index = arguments.firstIndex(of: "-overview-fixture"),
        arguments.indices.contains(index + 1)
      else { return nil }
      return arguments[index + 1]
    }

    static func session() -> URLSession {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [OverviewFixtureProtocol.self]
      return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
      guard let url = request.url else { return }
      if url.path.contains("/api/files/") {
        if url.lastPathComponent == "missing.png" {
          respond(object: [:], status: 404)
          return
        }
        respond(data: Self.artwork(), type: "image/png")
        return
      }
      if url.path.contains("/auth-with-password") {
        respond(object: [
          "token": "fictional-fixture-token",
          "record": ["id": "preview-user", "verified": true, "username": "Fictional crafter"],
        ])
        return
      }
      if url.path.contains("/users/") {
        respond(data: try! JSONEncoder().encode(UserRecord.preview))
        return
      }
      if url.path.contains("/user_dashboard_settings/") {
        respond(
          object: Self.list([
            [
              "id": "fictional-settings",
              "vertical_enabled": ["diamond_painting": true, "coloring_books": true],
            ]
          ]))
        return
      }
      if Self.scenario == "loading" { return }
      if Self.scenario == "error" {
        respond(object: ["message": "Fictional service failure"], status: 503)
        return
      }
      let filter =
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first(where: { $0.name == "filter" })?.value ?? ""
      if Self.scenario == "empty" || filter.contains("completed") || filter.contains("wishlist") {
        respond(object: Self.list([]))
      } else if url.path.contains("/projects/") {
        let items: [[String: Any]] = (1...5).map { index in
          [
            "id": "fictional-project-\(index)", "user": "preview-user",
            "title": index == 1 ? "Garden of stars" : "A small constellation, chapter \(index)",
            "status": "progress", "kit_category": "full",
            "image": index == 2 ? "" : index == 3 ? "missing.png" : "fictional-garden.png",
            "created": "2026-09-01", "updated": "2026-09-07 12:0\(index):00",
          ]
        }
        respond(object: Self.list(items))
      } else if url.path.contains("/coloring_pages/") {
        respond(
          object: Self.list([
            [
              "id": "fictional-page", "book": "fictional-book", "page_number": 12,
              "status": "in_progress", "photos": ["fictional-page.png"],
              "revealed_subject": "A moonlit garden with a very long, winding path",
              "created": "2026-09-01", "updated": "2026-09-07 13:00:00",
            ]
          ]))
      } else {
        respond(object: Self.list([]))
      }
    }

    private static func list(_ items: [[String: Any]]) -> [String: Any] {
      ["page": 1, "perPage": 5, "totalPages": 1, "totalItems": items.count, "items": items]
    }

    private func respond(object: [String: Any], status: Int = 200) {
      respond(data: try! JSONSerialization.data(withJSONObject: object), status: status)
    }

    private func respond(data: Data, type: String = "application/json", status: Int = 200) {
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil,
        headerFields: ["Content-Type": type]
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    }

    private static func artwork() -> Data {
      UIGraphicsImageRenderer(size: CGSize(width: 200, height: 260)).pngData { context in
        UIColor(red: 0.18, green: 0.23, blue: 0.34, alpha: 1).setFill()
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 260))
        UIColor(red: 0.93, green: 0.81, blue: 0.57, alpha: 1).setFill()
        context.cgContext.fillEllipse(in: CGRect(x: 120, y: 28, width: 45, height: 45))
        for index in 0..<6 {
          UIColor(red: 0.4, green: 0.65, blue: 0.54, alpha: 1).setFill()
          context.cgContext.fillEllipse(
            in: CGRect(x: 15 + index * 30, y: 115 + (index % 2) * 30, width: 25, height: 90)
          )
        }
      }
    }
  }
#endif
