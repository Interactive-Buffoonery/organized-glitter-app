import Foundation
import Testing

@testable import OrganizedGlitter

@MainActor
struct OfflineSessionTests {
  @Test func previouslyVerifiedAccountOpensItsDownloadedLibraryOffline() async throws {
    let (model, local, keychain, scope) = try await makeOfflineModel()
    defer { try? keychain.clear() }
    while model.phase == .restoring { await Task.yield() }
    #expect(model.phase == .signedIn(.preview))
    #expect(model.library?.hasSnapshot == true)
    #expect(try await local.loadUser(scope: scope) == .preview)
  }

  @Test func signOutRequiresExplicitDiscardAndRemovesOnlyItsAccount() async throws {
    let (model, local, keychain, scope) = try await makeOfflineModel()
    defer { try? keychain.clear() }
    while model.phase == .restoring { await Task.yield() }
    let project = featureProject("pending", title: "Original", user: scope.userID)
    try await local.ingest(.diamond(project), scope: scope)
    try await local.queueEdit(
      scope: scope, key: LocalRecordKey(kind: .project, id: project.id),
      patch: ["title": .string("Unsent title")])
    model.signOut()
    while model.isSigningOut { await Task.yield() }
    #expect(model.requiresDiscardConfirmation)
    #expect(model.library != nil)
    #expect(try await local.pendingCount(scope: scope) == 1)
    model.signOut(discardPending: true)
    while model.isSigningOut { await Task.yield() }
    #expect(model.phase == .signedOut)
    #expect(try await local.pendingCount(scope: scope) == 0)
    #expect(try await local.loadUser(scope: scope) == nil)
    #expect(try keychain.load() == nil)
  }

  @Test func expiredSessionPreservesPendingWorkForSameAccount() async throws {
    let (model, local, keychain, scope) = try await makeOfflineModel()
    defer { try? keychain.clear() }
    while model.phase == .restoring { await Task.yield() }
    let project = featureProject("pending", title: "Original", user: scope.userID)
    try await local.ingest(.diamond(project), scope: scope)
    try await local.queueEdit(
      scope: scope, key: LocalRecordKey(kind: .project, id: project.id),
      patch: ["title": .string("Unsent title")])
    await model.expireSession()
    #expect(model.phase == .signedOut)
    #expect(model.library == nil)
    #expect(try await local.pendingCount(scope: scope) == 1)
    let other = LocalAccountScope(backendURL: scope.backendURL, userID: "different-user")
    #expect(try await local.entries(scope: other).isEmpty)
  }

  @Test func passwordResetClosesLibraryAndPreservesPendingWork() async throws {
    let (model, local, keychain, scope) = try await makeOfflineModel()
    defer { try? keychain.clear() }
    while model.phase == .restoring { await Task.yield() }
    let project = featureProject("pending-reset", title: "Original", user: scope.userID)
    try await local.ingest(.diamond(project), scope: scope)
    try await local.queueEdit(
      scope: scope, key: LocalRecordKey(kind: .project, id: project.id),
      patch: ["title": .string("Unsent title")])

    await model.passwordResetConfirmed()

    #expect(model.phase == .signedOut)
    #expect(model.library == nil)
    #expect(try keychain.load() == nil)
    #expect(try await local.pendingCount(scope: scope) == 1)
    #expect(try await local.loadUser(scope: scope) == .preview)
  }

  @Test func pausedLibraryRejectsEditsBeforeSignOutChecksPendingWork() async throws {
    let library = try localFeatureLibrary()
    try await library.store.ingest(.diamond(featureProject("project", title: "Original")), scope: library.scope)
    library.pauseWrites()
    await #expect(throws: APIError.cancelled) {
      let _: DiamondProjectRecord = try await library.update(
        collection: "projects", id: "project", body: ["title": "Unsent"])
    }
    #expect(try await library.store.pendingCount(scope: library.scope) == 0)
  }

  @Test func launchRetriesInterruptedRemovalWithoutSavedCredentials() async throws {
    let local = try LocalLibraryStore.inMemory()
    let keychain = KeychainSessionStore(service: "OfflineCleanupTests.\(UUID().uuidString)")
    defer { try? keychain.clear() }
    let client = PocketBaseClient(
      baseURL: URL(string: "https://cleanup.example.invalid")!, sessionStore: keychain)
    let scope = LocalAccountScope(backendURL: client.baseURL, userID: UserRecord.preview.id)
    try await local.saveUser(.preview, scope: scope)
    try await local.ingest(.diamond(featureProject("private", title: "Private", user: scope.userID)), scope: scope)
    try await local.beginRemoval(scope: scope)
    let model = AppModel(client: client, sessionStore: keychain, themeStore: ThemeStore(), localStore: local)
    while model.phase == .restoring || model.phase == .cleaningLocalData { await Task.yield() }
    #expect(model.phase == .signedOut)
    #expect(try await local.entries(scope: scope).isEmpty)
    #expect(try await local.loadUser(scope: scope) == nil)
    #expect(try await local.pendingRemovals().isEmpty)
  }

  @Test func signOutDrainsAccountSaveAndRejectsConcurrentSignIn() async throws {
    let (model, local, keychain, scope) = try await makeOfflineModel()
    defer { try? keychain.clear() }
    while model.phase == .restoring { await Task.yield() }
    model.replaceSignedInUser(.preview)
    model.signOut(discardPending: true)
    #expect(model.isSigningOut)
    await model.signIn(identity: "ignored", password: "ignored")
    while model.isSigningOut { await Task.yield() }
    #expect(model.phase == .signedOut)
    #expect(try await local.loadUser(scope: scope) == nil)
    #expect(try await local.pendingRemovals().isEmpty)
  }

  @Test func cachedDataDoesNotCountAsAuthoritativeRefresh() async throws {
    let (model, _, keychain, _) = try await makeOfflineModel()
    defer { try? keychain.clear() }
    while model.phase == .restoring { await Task.yield() }
    let library = try #require(model.library)
    try await library.refresh()
    await #expect(throws: APIError.offline) { try await library.refreshFromServer() }
    #expect(library.hasSnapshot)
  }

  @Test func signOutNeverDiscardsAnAcceptedConcurrentEditWithoutConfirmation() async throws {
    for _ in 0..<20 {
      let (model, local, keychain, scope) = try await makeOfflineModel()
      defer { try? keychain.clear() }
      while model.phase == .restoring { await Task.yield() }
      let library = try #require(model.library)
      let project = featureProject("concurrent", title: "Original", user: scope.userID)
      try await local.ingest(.diamond(project), scope: scope)
      try await library.loadLocal()
      let edit = Task { () -> Bool in
        do {
          let _: DiamondProjectRecord = try await library.update(
            collection: "projects", id: project.id, body: ["title": "Unsent"])
          return true
        } catch { return false }
      }
      await Task.yield()
      model.signOut()
      let accepted = await edit.value
      while model.isSigningOut { await Task.yield() }
      if accepted {
        #expect(model.requiresDiscardConfirmation)
        #expect(try await local.pendingCount(scope: scope) == 1)
        model.signOut(discardPending: true)
        while model.isSigningOut { await Task.yield() }
      } else {
        #expect(model.phase == .signedOut)
      }
    }
  }

  private func makeOfflineModel() async throws
    -> (AppModel, LocalLibraryStore, KeychainSessionStore, LocalAccountScope)
  {
    let keychain = KeychainSessionStore(service: "OfflineSessionTests.\(UUID().uuidString)")
    try keychain.save(AuthenticatedSession(token: "fictional-token", user: .preview))
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OfflineSessionProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://offline-session.example.invalid")!, sessionStore: keychain,
      urlSession: URLSession(configuration: configuration))
    let local = try LocalLibraryStore.inMemory()
    let scope = LocalAccountScope(backendURL: client.baseURL, userID: UserRecord.preview.id)
    try await local.saveUser(.preview, scope: scope)
    let snapshot = LocalFullSnapshot(
      version: 1, projects: [], coloringBooks: [], coloringPages: [],
      progressNotes: [], coloringPageProgressNotes: [])
    try await local.ingestSnapshot(snapshot, scope: scope)
    let model = AppModel(client: client, sessionStore: keychain, themeStore: ThemeStore(), localStore: local)
    return (model, local, keychain, scope)
  }
}

private final class OfflineSessionProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
  }
  override func stopLoading() {}
}
