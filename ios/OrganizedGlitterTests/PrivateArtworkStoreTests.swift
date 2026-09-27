import Foundation
import Testing

@testable import OrganizedGlitter

struct PrivateArtworkStoreTests {
  @Test func downloadedArtworkIsScopedToAccountAndIgnoresTokenRotation() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PrivateArtworkStore(root: root)
    let backend = URL(string: "https://artwork.example.invalid")!
    let owner = LocalAccountScope(backendURL: backend, userID: "owner")
    let other = LocalAccountScope(backendURL: backend, userID: "other")
    let first = URL(string: "https://artwork.example.invalid/api/files/projects/record/photo.jpg?token=old&thumb=320x420")!
    let refreshed = URL(string: "https://artwork.example.invalid/api/files/projects/record/photo.jpg?token=new&thumb=320x420")!
    try await store.save(Data([1, 2, 3]), for: first, scope: owner)
    #expect(try await store.data(for: refreshed, scope: owner) == Data([1, 2, 3]))
    #expect(try await store.data(for: refreshed, scope: other) == nil)
    try await store.remove(scope: owner)
    #expect(try await store.data(for: refreshed, scope: owner) == nil)
  }

  @Test func emptyFileTokenCannotTriggerNetworkDownload() async throws {
    let backend = URL(string: "https://artwork.example.invalid")!
    let keychain = KeychainSessionStore(service: "PrivateArtworkTests.\(UUID().uuidString)")
    let client = PocketBaseClient(baseURL: backend, sessionStore: keychain)
    await client.prepareOfflineSession(StoredSession(token: "fictional", userID: UUID().uuidString))
    let url = client.fileURL(collection: "projects", recordID: "record", filename: "photo.jpg", token: "")
    await #expect(throws: APIError.offline) { try await client.fileData(at: url, maximumByteCount: 100) }
  }

  @Test func fileRequestRejectsDifferentOriginBeforeAttachingCredentials() async throws {
    let keychain = KeychainSessionStore(service: "PrivateArtworkTests.\(UUID().uuidString)")
    let client = PocketBaseClient(baseURL: URL(string: "https://artwork.example.invalid")!, sessionStore: keychain)
    await client.prepareOfflineSession(StoredSession(token: "fictional", userID: UUID().uuidString))
    await #expect(throws: APIError.forbidden) {
      try await client.fileData(at: URL(string: "https://other.example.invalid/api/files/p/r/f?token=x")!, maximumByteCount: 100)
    }
  }
}
