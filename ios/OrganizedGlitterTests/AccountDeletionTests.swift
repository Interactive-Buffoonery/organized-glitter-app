import Foundation
import Testing
@testable import OrganizedGlitter

@MainActor
@Suite(.serialized)
struct AccountDeletionTests {
  @Test func proofIsThirtyTwoRandomBytesEncodedAsBase64URL() throws {
    let a = try AccountDeletionIntent.makeProof()
    #expect(a.count == 43)
    #expect(a.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil)
    #expect(a != (try AccountDeletionIntent.makeProof()))
  }

  @Test func confirmedDeletionRemovesActualPendingLibraryAndKeychainIntent() async throws {
    let f = try await fixture()
    defer { try? f.store.clear(); try? f.store.deletionPersistence.clear() }
    let local = try LocalLibraryStore.inMemory()
    let scope = f.model.scope
    let other = LocalAccountScope(backendURL: scope.backendURL, userID: "other-account")
    let user = try JSONDecoder().decode(UserRecord.self, from: Data(#"{"id":"user-a","verified":true}"#.utf8))
    let otherUser = try JSONDecoder().decode(UserRecord.self, from: Data(#"{"id":"other-account","verified":true}"#.utf8))
    try await local.saveUser(user, scope: scope)
    try await local.saveUser(otherUser, scope: other)
    let project = featureProject("project-a", title: "Fictional project", user: scope.userID)
    try await local.ingest(.diamond(project), scope: scope)
    try await local.queueEdit(scope: scope, key: LocalRecordKey(kind: .project, id: project.id), patch: ["title": .string("Unsent edit")])
    let app = AppModel(client: f.client, sessionStore: f.store, themeStore: ThemeStore(), localStore: local)
    while app.phase == .restoring { await Task.yield() }
    DeletionWire.responses = [(200, #"{"token":"original","record":{"id":"user-a","verified":true}}"#)]
    await app.signIn(identity: "fictional", password: "fictional")
    #expect(app.library?.pendingCount == 1)
    app.beginAccountDeletion()
    let deletion = try #require(app.deletion)
    DeletionWire.responses = [(204, ""), (200, #"{"status":"deleted","cleanup":"pending"}"#)]
    await deletion.verifyPassword("fictional")
    await deletion.confirm()
    #expect(deletion.state == .completed(.pending))
    #expect(app.library == nil)
    #expect(try f.store.load() == nil)
    #expect(try f.store.deletionPersistence.load() == nil)
    #expect(try await local.pendingCount(scope: scope) == 0)
    #expect(try await local.loadUser(scope: scope) == nil)
    #expect(try await local.loadUser(scope: other) == otherUser)
    #expect(try await local.pendingRemovals().isEmpty)
  }

  @Test func uncertainDeletionKeepsPendingEditsLockedAcrossRelaunchUntilSameProofSucceeds() async throws {
    let f = try await fixture()
    defer { try? f.store.clear(); try? f.store.deletionPersistence.clear() }
    let local = try LocalLibraryStore.inMemory()
    let scope = f.model.scope
    let user = try JSONDecoder().decode(UserRecord.self,
      from: Data(#"{"id":"user-a","verified":true}"#.utf8))
    try await local.saveUser(user, scope: scope)
    let project = featureProject("project-locked", title: "Fictional project", user: scope.userID)
    try await local.ingest(.diamond(project), scope: scope)
    try await local.queueEdit(scope: scope,
      key: LocalRecordKey(kind: .project, id: project.id),
      patch: ["title": .string("Unsent edit")])
    let first = AppModel(client: f.client, sessionStore: f.store, themeStore: ThemeStore(), localStore: local)
    while first.phase == .restoring { await Task.yield() }
    DeletionWire.responses = [(200, #"{"token":"original","record":{"id":"user-a","verified":true}}"#)]
    await first.signIn(identity: "fictional", password: "fictional")
    first.beginAccountDeletion()
    let deletion = try #require(first.deletion)
    DeletionWire.responses = [(204, ""), (401, "{}")]
    await deletion.verifyPassword("fictional")
    let proof = try #require(f.store.deletionPersistence.load()?.proof)
    await deletion.confirm()
    #expect(first.phase == .accountDeletion)
    #expect(deletion.state == .uncertain)
    #expect(try await local.pendingCount(scope: scope) == 1)
    #expect(try f.store.deletionPersistence.load()?.stage == .submitted)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [DeletionWire.self]
    let resumedClient = PocketBaseClient(baseURL: scope.backendURL, sessionStore: f.store,
      urlSession: URLSession(configuration: config))
    let resumed = AppModel(client: resumedClient, sessionStore: f.store,
      themeStore: ThemeStore(), localStore: local)
    #expect(resumed.phase == .accountDeletion)
    #expect(try await local.pendingCount(scope: scope) == 1)
    DeletionWire.responses = [(401, "{}")]
    await resumed.deletion?.retry()
    #expect(resumed.deletion?.state == .uncertain)
    #expect(try f.store.deletionPersistence.load()?.proof == proof)

    DeletionWire.responses = [(204, ""), (200, #"{"status":"deleted","cleanup":"pending"}"#)]
    await resumed.deletion?.reverifyPassword("fictional")
    #expect(resumed.deletion?.state == .resubmissionReady)
    await resumed.deletion?.confirmResubmission()
    #expect(resumed.deletion?.state == .completed(.pending))
    #expect(try await local.pendingCount(scope: scope) == 0)
    #expect(try await local.loadUser(scope: scope) == nil)
  }

  @Test func keychainIntentRoundTripsAndDoesNotReplaceSessionCredentials() throws {
    let service = "deletion.keychain.\(UUID().uuidString)"
    let store = KeychainDeletionIntentStore(service: service)
    let session = KeychainSessionStore(service: service)
    defer { try? store.clear(); try? session.clear() }
    let intent = AccountDeletionIntent(backendURL: URL(string: "https://example.test")!, userID: "account-a", proof: try AccountDeletionIntent.makeProof())
    try store.save(intent)
    #expect(try store.load() == intent)
    #expect(try session.load() == nil)
    try store.clear()
    #expect(try store.load() == nil)
  }

  @Test func failedSubmittedWriteNeverSendsAndPreservesPreparedProof() async throws {
    let f = try await fixture()
    await f.model.verifyPassword("example")
    f.disk.failSave = true
    await f.model.confirm()
    #expect(f.model.state == .blocked)
    #expect(f.disk.intent?.stage == .prepared)
    #expect(!DeletionWire.requests.contains { $0.url?.path == "/api/account/delete" })
  }

  @Test func expiredProofCannotSubmit() async throws {
    let clock = DeletionClock()
    let f = try await fixture(now: { clock.date })
    await f.model.verifyPassword("example")
    clock.date = clock.date.addingTimeInterval(300)
    await f.model.confirm()
    #expect(f.model.state == .idle)
    #expect(f.disk.intent == nil)
    #expect(!DeletionWire.requests.contains { $0.url?.path == "/api/account/delete" })
  }

  @Test func oauthStepUpUsesExistingIdentityFieldsAndDiscardsReturnedToken() async throws {
    let f = try await fixture()
    DeletionWire.responses = [
      (200, #"{"oauth2":{"enabled":true,"providers":[{"name":"google","authURL":"https://provider.example.test/auth?redirect_uri=","state":"state","codeVerifier":"verifier"}]}}"#),
      (200, #"{"token":"discard-this-token","record":{"id":"user-a","verified":true}}"#),
      (200, #"{"status":"deleted","cleanup":"pending"}"#),
    ]
    await f.model.verifyOAuth(provider: .google, present: { _, redirect in URL(string: redirect.absoluteString + "?state=state&code=fictional")! })
    #expect(f.model.state == .ready)
    let exchange = try #require(JSONSerialization.jsonObject(with: DeletionWire.bodies[1]) as? [String: Any])
    let createData = try #require(exchange["createData"] as? [String: String])
    #expect(createData["og_step_up_action"] == "delete_account")
    #expect(createData["og_step_up_target_provider"] == "account")
    #expect(createData["og_step_up_user_id"] == "user-a")
    #expect(DeletionWire.requests[1].value(forHTTPHeaderField: "Authorization") == nil)
    await f.model.confirm()
    #expect(DeletionWire.requests.last?.value(forHTTPHeaderField: "Authorization") == "original")
    #expect(try f.store.load() == nil)
  }

  @Test func failedProofWriteNeverSubmitsDeletion() async throws {
    let f = try await fixture()
    f.disk.failSave = true
    await f.model.verifyPassword("example")
    #expect(f.model.state == .blocked)
    #expect(DeletionWire.requests.isEmpty)
    #expect(f.disk.cleanupCount == 0)
    f.disk.failSave = false
    await f.model.verifyPassword("example")
    #expect(f.model.state == .ready)
  }

  @Test func lostResponseLocksAndRestartRetriesSameProofWithoutToken() async throws {
    let f = try await fixture()
    await f.model.verifyPassword("example")
    #expect(f.model.state == .ready)
    DeletionWire.responses = [(503, "{}")]
    await f.model.confirm()
    #expect(f.model.state == .uncertain)
    let submitted = try #require(f.disk.intent)
    #expect(submitted.stage == .submitted)
    #expect(f.disk.cleanupCount == 0)
    let recovered = makeModel(client: f.client, disk: f.disk)
    #expect(try recovered.recover())
    DeletionWire.responses = [(200, #"{"status":"deleted","cleanup":"pending"}"#)]
    await recovered.retry()
    #expect(recovered.state == .completed(.pending))
    #expect(f.disk.intent == nil)
    #expect(f.disk.cleanupCount == 1)
    let last = try #require(DeletionWire.requests.last)
    #expect(last.value(forHTTPHeaderField: "Authorization") == nil)
    let json = try #require(JSONSerialization.jsonObject(with: DeletionWire.bodies.last!) as? [String: Any])
    #expect(json["proof"] as? String == submitted.proof)
    #expect(json["confirmed"] as? Bool == true)
    #expect(Set(json.keys) == ["proof", "confirmed"])
  }

  @Test func unknownProofAndMalformedSuccessNeverCleanLocalData() async throws {
    for response in [(401, "{}"), (200, "{}"), (200, #"{"status":"deleted","cleanup":"other"}"#)] {
      let f = try await fixture()
      await f.model.verifyPassword("example")
      DeletionWire.responses = [response]
      await f.model.confirm()
      #expect(f.model.state == .uncertain)
      #expect(f.disk.intent?.stage == .submitted)
      #expect(f.disk.cleanupCount == 0)
      #expect(DeletionWire.requests.filter { $0.url?.path == "/api/account/delete" }.count == 1)
      #expect(!DeletionWire.requests.contains { $0.url?.path.contains("auth-refresh") == true })
    }
  }

  @Test func sessionSwitchAfterDispatchRetainsIntentAndNeverCleansAnotherAccount() async throws {
    let f = try await fixture()
    await f.model.verifyPassword("example")
    DeletionWire.holdDeletion = true
    let task = Task { await f.model.confirm() }
    let deadline = ContinuousClock.now + .seconds(5)
    while DeletionWire.pending == nil, ContinuousClock.now < deadline { await Task.yield() }
    let pending = try #require(DeletionWire.pending)
    await f.client.prepareOfflineSession(StoredSession(token: "other-session", userID: "other-account"))
    pending.finishPending(status: 200, body: #"{"status":"deleted","cleanup":"pending"}"#)
    await task.value
    #expect(f.model.state == .uncertain)
    #expect(f.disk.intent?.stage == .submitted)
    #expect(f.disk.cleanupCount == 0)
  }

  @Test func leavingPreparationCannotDismissCompletedReceipt() async throws {
    let f = try await fixture()
    await f.model.verifyPassword("example")
    DeletionWire.responses = [(200, #"{"status":"deleted","cleanup":"pending"}"#)]
    await f.model.confirm()
    #expect(f.model.state == .completed(.pending))
    f.model.cancelPreparation()
    #expect(f.model.state == .completed(.pending))
  }

  @Test func cancelledDispatchedRequestRetainsRecoveryProof() async throws {
    let f = try await fixture()
    await f.model.verifyPassword("example")
    DeletionWire.holdDeletion = true
    let task = Task { await f.model.confirm() }
    let deadline = ContinuousClock.now + .seconds(5)
    while DeletionWire.pending == nil, ContinuousClock.now < deadline { await Task.yield() }
    _ = try #require(DeletionWire.pending)
    task.cancel()
    await task.value
    #expect(f.model.state == .uncertain)
    #expect(f.disk.intent?.stage == .submitted)
    #expect(f.disk.cleanupCount == 0)
    DeletionWire.pending = nil
  }

  @Test func failedConfirmedIntentWritePreventsCleanupUntilDurableRetry() async throws {
    let f = try await fixture()
    await f.model.verifyPassword("example")
    f.disk.failConfirmedSave = true
    DeletionWire.responses = [(200, #"{"status":"deleted","cleanup":"pending"}"#)]
    await f.model.confirm()
    #expect(f.model.state == .localCleanupFailed(.pending))
    #expect(f.disk.cleanupCount == 0)
    #expect(f.disk.intent?.stage == .submitted)
    let count = DeletionWire.requests.count
    f.disk.failConfirmedSave = false
    await f.model.retry()
    #expect(f.model.state == .completed(.pending))
    #expect(DeletionWire.requests.count == count)
  }

  @Test func failedFinalIntentClearRetainsConfirmedCleanupForRetry() async throws {
    let f = try await fixture()
    await f.model.verifyPassword("example")
    f.disk.failClear = true
    DeletionWire.responses = [(200, #"{"status":"deleted","cleanup":"pending"}"#)]
    await f.model.confirm()
    #expect(f.model.state == .localCleanupFailed(.pending))
    #expect(f.disk.intent?.stage == .serverDeleted)
    f.disk.failClear = false
    await f.model.retry()
    #expect(f.model.state == .completed(.pending))
    #expect(f.disk.intent == nil)
  }

  @Test func cancellationBeforeSubmissionRemovesOnlyPreparedIntent() async throws {
    let f = try await fixture()
    await f.model.verifyPassword("example")
    f.model.cancelPreparation()
    await f.model.confirm()
    #expect(f.disk.intent == nil)
    #expect(f.disk.cleanupCount == 0)
    #expect(!DeletionWire.requests.contains { $0.url?.path == "/api/account/delete" })
  }

  @Test func cleanupFailureSurvivesRestartWithoutRepeatingDeletion() async throws {
    let f = try await fixture()
    await f.model.verifyPassword("example")
    f.disk.failCleanup = true
    DeletionWire.responses = [(200, #"{"status":"deleted","cleanup":"completed"}"#)]
    await f.model.confirm()
    #expect(f.model.state == .localCleanupFailed(.completed))
    #expect(f.disk.intent?.stage == .serverDeleted)
    let count = DeletionWire.requests.count
    f.disk.failCleanup = false
    let recovered = makeModel(client: f.client, disk: f.disk)
    #expect(try recovered.recover())
    await recovered.retry()
    #expect(recovered.state == .completed(.completed))
    #expect(DeletionWire.requests.count == count)
  }

  @Test func neverDispatchedDeletionCanBeReverifiedWithSameProofAndExplicitlyRetried() async throws {
    let f = try await fixture()
    await f.model.verifyPassword("example")
    let originalProof = try #require(f.disk.intent?.proof)
    f.disk.failLock = true
    await f.model.confirm()
    #expect(f.model.state == .uncertain)
    #expect(f.disk.intent?.stage == .submitted)
    #expect(!DeletionWire.requests.contains { $0.url?.path == "/api/account/delete" })

    f.disk.failLock = false
    DeletionWire.responses = [(401, "{}")]
    await f.model.retry()
    #expect(f.model.state == .uncertain)
    #expect(f.disk.intent?.proof == originalProof)
    #expect(f.disk.cleanupCount == 0)

    DeletionWire.responses = [(204, ""), (200, #"{"status":"deleted","cleanup":"pending"}"#)]
    await f.model.reverifyPassword("example")
    #expect(f.model.state == .resubmissionReady)
    #expect(f.disk.intent?.proof == originalProof)
    await f.model.confirmResubmission()
    #expect(f.model.state == .completed(.pending))
    let delete = try #require(DeletionWire.requests.last { $0.url?.path == "/api/account/delete" })
    #expect(delete.value(forHTTPHeaderField: "Authorization") == "original")
    let body = try #require(JSONSerialization.jsonObject(with: DeletionWire.bodies.last!) as? [String: Any])
    #expect(body["proof"] as? String == originalProof)
  }

  @Test func availableMethodsRequireProviderReadinessAndAccountConnection() async throws {
    let f = try await fixture()
    DeletionWire.responsesByPath = [
      "/api/collections/users/auth-methods": (200, #"{"password":{"enabled":true},"oauth2":{"enabled":true,"providers":[{"name":"google","state":"s","authURL":"https://example.test","codeVerifier":"v"}]}}"#),
      "/api/collections/users/records/user-a/external-auths": (200, #"[{"provider":"google"},{"provider":"discord"}]"#),
    ]
    defer { DeletionWire.responsesByPath = [:] }
    await f.model.loadMethods()
    let methods = try #require(f.model.methods)
    #expect(methods.passwordAvailable)
    #expect(methods.socialProviders == [.google])
    #expect(!methods.appleLinked)
    #expect(!methods.appleAvailable)
    #expect(!f.model.methodLoadFailed)
    DeletionWire.responsesByPath = [
      "/api/collections/users/auth-methods": (200, #"{"password":{"enabled":true},"oauth2":{"enabled":false,"providers":[]}}"#),
      "/api/collections/users/records/user-a/external-auths": (200, #"[{"provider":"apple"}]"#),
      "/api/auth/apple/native/readiness": (200, #"{"available":false}"#),
    ]
    await f.model.loadMethods()
    #expect(f.model.methods?.appleLinked == true)
    #expect(f.model.methods?.appleAvailable == false)
    #expect(f.model.methods?.passwordAvailable == true)
  }

  @Test func wrongBackendRecoveryFailsClosed() async throws {
    let f = try await fixture()
    f.disk.intent = AccountDeletionIntent(backendURL: URL(string: "https://other.test")!, userID: "user-a", proof: try AccountDeletionIntent.makeProof())
    #expect(throws: (any Error).self) { try f.model.recover() }
    #expect(f.disk.intent != nil)
    #expect(DeletionWire.requests.isEmpty)
  }

  @Test func sessionSwitchDuringStepUpCannotAuthorizeDeletion() async throws {
    let f = try await fixture()
    await f.client.signOut()
    await f.model.verifyPassword("example")
    #expect(f.model.state != .ready)
    #expect(f.disk.cleanupCount == 0)
  }

  @Test func sessionInvalidationPreventsSubmission() async throws {
    let f = try await fixture(now: { Date(timeIntervalSince1970: 100) })
    await f.model.verifyPassword("example")
    f.model.invalidate()
    await f.model.confirm()
    #expect(f.disk.cleanupCount == 0)
    #expect(!DeletionWire.requests.contains { $0.url?.path == "/api/account/delete" })
  }

  @Test func appleWrongIdentityDoesNotReplaceSessionOrAuthorizeDeletion() async throws {
    let f = try await fixture()
    DeletionWire.responses = [(200, #"{"token":"discard-me","record":{"id":"other","verified":true}}"#)]
    await #expect(throws: (any Error).self) {
      try await f.client.verifyDeletionWithApple(scope: f.model.scope, proof: try AccountDeletionIntent.makeProof(), code: "example", nonce: "example")
    }
    #expect(try f.store.load() == nil)
    #expect(DeletionWire.requests.last?.value(forHTTPHeaderField: "Authorization") == nil)
  }

  private func fixture(now: @escaping () -> Date = Date.init) async throws -> (model: AccountDeletionModel, disk: DeletionDisk, client: PocketBaseClient, store: KeychainSessionStore) {
    DeletionWire.requests = []; DeletionWire.bodies = []; DeletionWire.responses = [(204, "")]; DeletionWire.holdDeletion = false; DeletionWire.pending = nil
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [DeletionWire.self]
    let store = KeychainSessionStore(service: "deletion.tests.\(UUID().uuidString)")
    let client = PocketBaseClient(baseURL: URL(string: "https://example.test")!, sessionStore: store, urlSession: URLSession(configuration: config))
    await client.prepareOfflineSession(StoredSession(token: "original", userID: "user-a"))
    let disk = DeletionDisk()
    return (makeModel(client: client, disk: disk, now: now), disk, client, store)
  }

  private func makeModel(client: PocketBaseClient, disk: DeletionDisk, now: @escaping () -> Date = Date.init) -> AccountDeletionModel {
    AccountDeletionModel(client: client, scope: LocalAccountScope(backendURL: client.baseURL, userID: "user-a"), persistence: AccountDeletionPersistence(load: { disk.intent }, save: { if disk.failSave || (disk.failConfirmedSave && $0.stage == .serverDeleted) { throw APIError.server }; disk.intent = $0 }, clear: { if disk.failClear { throw APIError.server }; disk.intent = nil }), now: now, lock: { if disk.failLock { throw APIError.server } }, cleanup: { _ in if disk.failCleanup { throw APIError.server }; disk.cleanupCount += 1 })
  }
}

@MainActor private final class DeletionDisk {
  var intent: AccountDeletionIntent?
  var failSave = false
  var failConfirmedSave = false
  var failClear = false
  var failCleanup = false
  var failLock = false
  var cleanupCount = 0
}

private final class DeletionWire: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var savedRequests: [URLRequest] = []
  nonisolated(unsafe) private static var savedBodies: [Data] = []
  nonisolated(unsafe) private static var savedResponses: [(Int, String)] = []
  nonisolated(unsafe) private static var savedResponsesByPath: [String: (Int, String)] = [:]
  nonisolated(unsafe) private static var savedHold = false
  nonisolated(unsafe) private static var savedPending: DeletionWire?
  static var requests: [URLRequest] { get { lock.withLock { savedRequests } } set { lock.withLock { savedRequests = newValue } } }
  static var bodies: [Data] { get { lock.withLock { savedBodies } } set { lock.withLock { savedBodies = newValue } } }
  static var responses: [(Int, String)] { get { lock.withLock { savedResponses } } set { lock.withLock { savedResponses = newValue } } }
  static var responsesByPath: [String: (Int, String)] {
    get { lock.withLock { savedResponsesByPath } }
    set { lock.withLock { savedResponsesByPath = newValue } }
  }
  static var holdDeletion: Bool { get { lock.withLock { savedHold } } set { lock.withLock { savedHold = newValue } } }
  static var pending: DeletionWire? { get { lock.withLock { savedPending } } set { lock.withLock { savedPending = newValue } } }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.lock.withLock { Self.savedRequests.append(request) }
    var data = request.httpBody ?? Data()
    if let stream = request.httpBodyStream {
      stream.open(); defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 2048)
      while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(buffer, count: count) }
    }
    Self.lock.withLock { Self.savedBodies.append(data) }
    if Self.holdDeletion, request.url?.path == "/api/account/delete" {
      Self.pending = self
      return
    }
    let next = Self.lock.withLock {
      if let path = request.url?.path, let response = Self.savedResponsesByPath[path] { return response }
      return Self.savedResponses.isEmpty ? (500, "{}") : Self.savedResponses.removeFirst()
    }
    finishPending(status: next.0, body: next.1)
  }
  func finishPending(status: Int, body: String) {
    Self.pending = nil
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@MainActor private final class DeletionClock { var date = Date(timeIntervalSince1970: 100) }
