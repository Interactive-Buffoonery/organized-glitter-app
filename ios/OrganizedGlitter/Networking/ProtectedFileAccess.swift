import Foundation
import Observation
import SwiftUI

/// Owns only the short-lived file token for the currently displayed account.
@MainActor
@Observable
final class ProtectedFileAccess {
  private(set) var token: String?
  private let client: PocketBaseClient
  private var generation = 0

  init(client: PocketBaseClient) {
    self.client = client
  }

  func run() async {
    generation &+= 1
    let currentGeneration = generation
    token = nil
    defer {
      if generation == currentGeneration { token = nil }
    }
    while !Task.isCancelled {
      do {
        let nextToken = try await client.fileToken()
        guard !Task.isCancelled, generation == currentGeneration else { return }
        if token != nextToken { token = nextToken }
        try await Task.sleep(for: .seconds(Self.renewalDelay(for: nextToken)))
      } catch is CancellationError {
        return
      } catch {
        guard generation == currentGeneration else { return }
        if case APIError.unauthenticated = error { token = nil }
        if case APIError.forbidden = error { token = nil }
        try? await Task.sleep(for: .seconds(10))
      }
    }
  }

  static func renewalDelay(for token: String, now: Date = .now) -> TimeInterval {
    let parts = token.split(separator: ".")
    guard parts.count == 3 else { return 30 }
    var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
    guard let data = Data(base64Encoded: payload),
      let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let expiration = claims["exp"] as? TimeInterval
    else { return 30 }
    let timeUntilExpiry = expiration - now.timeIntervalSince1970
    guard timeUntilExpiry > 0 else { return 30 }
    return max(30, timeUntilExpiry - 30)
  }

  func artworkURL(for item: LibraryItem, thumb: String? = nil) -> URL? {
    item.artworkURL(using: client, thumb: thumb, token: token ?? "")
  }

  func photoURL(for note: ProgressNoteItem, thumb: String? = nil) -> URL? {
    guard let image = note.image?.nonEmpty else { return nil }
    return url(
      collection: note.collection, recordID: note.recordID,
      filename: image, thumb: thumb)
  }

  func url(
    collection: String,
    recordID: String,
    filename: String,
    thumb: String? = nil
  ) -> URL? {
    return client.fileURL(
      collection: collection, recordID: recordID, filename: filename,
      thumb: thumb, token: token ?? ""
    )
  }
}

private struct ProtectedFilesKey: EnvironmentKey {
  static let defaultValue: ProtectedFileAccess? = nil
}

extension EnvironmentValues {
  var protectedFiles: ProtectedFileAccess? {
    get { self[ProtectedFilesKey.self] }
    set { self[ProtectedFilesKey.self] = newValue }
  }
}
