import Foundation
import Testing
@testable import OrganizedGlitter

@MainActor
@Suite(.serialized)
struct AccountActionsTests {
  @Test(arguments: [200, 401, 503])
  func acceptedPasswordClearsOldSessionAndPreservesPendingEdits(reauthStatus: Int) async throws {
    let (model, client, store, localStore) = try await accountModel()
    defer { try? store.clear() }
    let library = try #require(model.library)
    let project = featureProject("pending-project", title: "Original", user: "account-owner")
    try await localStore.ingest(.diamond(project), scope: library.scope)
    _ = try await localStore.queueEdit(
      scope: library.scope, key: .init(kind: .project, id: project.id),
      patch: ["title": .string("Pending title")])
    try await library.loadLocal()
    let operation = try #require(await localStore.pendingOperations(scope: library.scope).first)
    AccountActionProtocol.reauthStatus = reauthStatus
    var accepted = false

    let outcome = try await model.changePassword(
      oldPassword: "OldExample1", password: "NewExample2", confirmation: "NewExample2",
      library: library, onAccepted: { accepted = true })

    #expect(accepted)
    #expect(AccountActionProtocol.oldSessionWasCleared)
    #expect(try await localStore.pendingOperations(scope: library.scope).first?.id == operation.id)
    #expect(try await localStore.entry(scope: library.scope, key: .init(kind: .project, id: project.id))?.item.title
      == "Pending title")
    if reauthStatus == 200 {
      #expect(outcome == .changed)
      #expect(model.library === library)
      #expect(try store.load()?.token == "new-token")
    } else {
      #expect(outcome == .changedSignInRequired)
      #expect(model.phase == .signedOut)
      #expect(model.library == nil)
      #expect(try store.load() == nil)
    }
    try await model.library?.close(removingData: false)
    await client.signOut()
  }

  @Test
  func rejectedPasswordDoesNotClearSessionOrAnnounceAcceptance() async throws {
    let (model, client, store, _) = try await accountModel()
    defer { try? store.clear() }
    let library = try #require(model.library)
    AccountActionProtocol.patchStatus = 400
    var accepted = false
    await #expect(throws: APIError.validation("Failed to update record.")) {
      _ = try await model.changePassword(
        oldPassword: "WrongExample1", password: "NewExample2", confirmation: "NewExample2",
        library: library, onAccepted: { accepted = true })
    }
    #expect(!accepted)
    #expect(try store.load()?.token == "old-token")
    #expect(AccountActionProtocol.authRequests == 1)
    #expect(model.library === library)
    try await model.library?.close(removingData: false)
    await client.signOut()
  }

  @Test
  func emailRequestKeepsConfirmedIdentity() async throws {
    let (model, client, store, _) = try await accountModel()
    defer { try? store.clear() }
    let before = model.phase
    try await model.requestEmailChange(email: "new@example.test", library: #require(model.library))
    #expect(model.phase == before)
    #expect(try store.load()?.token == "old-token")
    try await model.library?.close(removingData: false)
    await client.signOut()
  }

  @Test
  func passwordReauthenticationRejectsAnotherOwner() async throws {
    let (model, client, store, _) = try await accountModel()
    defer { try? store.clear() }
    AccountActionProtocol.reauthOwner = "another-owner"
    let outcome = try await model.changePassword(
      oldPassword: "OldExample1", password: "NewExample2", confirmation: "NewExample2",
      library: #require(model.library), onAccepted: {})
    #expect(outcome == .changedSignInRequired)
    #expect(model.phase == .signedOut)
    #expect(try store.load() == nil)
    try await model.library?.close(removingData: false)
    await client.signOut()
  }

  @Test
  func latePasswordReauthenticationCannotRestoreExpiredSession() async throws {
    let (model, _, store, _) = try await accountModel()
    defer { try? store.clear() }
    let library = try #require(model.library)
    AccountActionProtocol.reauthDelay = 0.1
    let task = Task {
      try await model.changePassword(
        oldPassword: "OldExample1", password: "NewExample2", confirmation: "NewExample2",
        library: library, onAccepted: {})
    }
    while AccountActionProtocol.authRequests < 2 { await Task.yield() }
    await model.expireSession()
    await #expect(throws: APIError.cancelled) { _ = try await task.value }
    #expect(model.phase == .signedOut)
    #expect(try store.load() == nil)
  }

  private func accountModel() async throws
    -> (AppModel, PocketBaseClient, KeychainSessionStore, LocalLibraryStore)
  {
    AccountActionProtocol.reset()
    let store = KeychainSessionStore(service: "AccountActions.\(UUID().uuidString)")
    AccountActionProtocol.store = store
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AccountActionProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!, sessionStore: store,
      urlSession: URLSession(configuration: configuration))
    let localStore = try LocalLibraryStore.inMemory()
    let model = AppModel(
      client: client, sessionStore: store, themeStore: ThemeStore(), localStore: localStore)
    while model.phase == .restoring { await Task.yield() }
    await model.signIn(identity: "account@example.test", password: "OldExample1")
    #expect(model.library != nil)
    return (model, client, store, localStore)
  }
}

private final class AccountActionProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var store: KeychainSessionStore?
  nonisolated(unsafe) static var patchStatus = 200
  nonisolated(unsafe) static var reauthStatus = 200
  nonisolated(unsafe) static var reauthOwner = "account-owner"
  nonisolated(unsafe) static var reauthDelay: TimeInterval = 0
  nonisolated(unsafe) static var authRequests = 0
  nonisolated(unsafe) static var oldSessionWasCleared = false

  static func reset() {
    store = nil
    patchStatus = 200
    reauthStatus = 200
    reauthOwner = "account-owner"
    reauthDelay = 0
    authRequests = 0
    oldSessionWasCleared = false
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  override func startLoading() {
    let path = request.url!.path
    var status = 200
    var body = "{}"
    if path.hasSuffix("auth-with-password") {
      Self.authRequests += 1
      let reauth = Self.authRequests > 1
      if reauth {
        Self.oldSessionWasCleared = (try? Self.store?.load()) == nil
        status = Self.reauthStatus
        if Self.reauthDelay > 0 { Thread.sleep(forTimeInterval: Self.reauthDelay) }
      }
      let owner = reauth ? Self.reauthOwner : "account-owner"
      let token = reauth ? "new-token" : "old-token"
      body = "{\"token\":\"\(token)\",\"record\":{\"id\":\"\(owner)\",\"email\":\"account@example.test\",\"verified\":true}}"
    } else if request.httpMethod == "PATCH" {
      status = Self.patchStatus
      body = status == 200 ? "accepted response without JSON" : #"{"status":400,"message":"Failed to update record.","data":{"oldPassword":{"code":"validation_invalid_old_password","message":"Missing or invalid old password."}}}"#
    } else if path.hasSuffix("request-email-change") {
      status = 204
    } else {
      status = 503
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
}
