import Foundation
import SwiftData
import Testing
@testable import OrganizedGlitter

@MainActor
@Suite(.serialized)
struct PageMediumSaveTests {
  @Test
  func onlineApplyPreservesBaselineOrderAndCommitsOnlyMediums() async throws {
    let library = try await makeLibrary(ids: ["z", "a"])
    defer { library.pauseWrites() }
    let page = try await library.savePageMediums(
      pageID: "page", baseline: ["z", "a"], selection: ["unexpanded", "a"], connected: true)
    #expect(page.mediumIDs == ["a", "unexpanded"])
    let body = try #require(MediumSaveProtocol.bodies.first)
    #expect(body["collection"] as? String == "coloring_pages")
    #expect((body["base"] as? [String: [String]]) == ["mediums": ["z", "a"]])
    #expect((body["patch"] as? [String: [String]]) == ["mediums": ["a", "unexpanded"]])
    #expect(library.mediumAttempts.isEmpty)
    #expect(try await library.store.pendingOperations(scope: library.scope).isEmpty)
    let cached: ColoringPageRecord = try library.record(collection: "coloring_pages", id: "page")
    #expect(cached.mediumIDs == page.mediumIDs)
  }

  @Test
  func clearSelectionAndStatusOnlyConcurrentChangeSucceed() async throws {
    let library = try await makeLibrary(ids: ["a"])
    defer { library.pauseWrites() }
    MediumSaveProtocol.page["status"] = "completed"
    let page = try await library.savePageMediums(
      pageID: "page", baseline: ["a"], selection: [], connected: true)
    #expect(page.mediumIDs == [])
    #expect(page.status == "completed")
  }

  @Test
  func twoDevicesKeepConflictingDraftUntilExplicitReapply() async throws {
    let library = try await makeLibrary(ids: ["a"])
    defer { library.pauseWrites() }
    MediumSaveProtocol.page["mediums"] = ["other-device"]
    await #expect(throws: LocalSyncConflict.self) {
      try await library.savePageMediums(
        pageID: "page", baseline: ["a"], selection: ["mine"], connected: true)
    }
    let draft = try #require(library.mediumAttempts.first)
    #expect(draft.state == .conflict)
    #expect(draft.patch.mediums == ["mine"])
    #expect(draft.current?.mediumIDs == ["other-device"])
    await #expect(throws: PageMediumSaveError.needsReview) {
      try await library.resumePageMediums(draft.id, connected: true)
    }
    let saved = try await library.savePageMediums(
      pageID: "page", baseline: ["other-device"], selection: ["mine"], connected: true,
      replacing: draft.id)
    #expect(saved.mediumIDs == ["mine"])
    #expect(MediumSaveProtocol.bodies.count == 2)
    #expect(MediumSaveProtocol.bodies[0]["operationId"] as? String
      != MediumSaveProtocol.bodies[1]["operationId"] as? String)
  }

  @Test
  func conflictingDraftCanBeDiscardedWithoutAnotherRequest() async throws {
    let library = try await makeLibrary(ids: ["a"])
    defer { library.pauseWrites() }
    MediumSaveProtocol.page["mediums"] = ["other-device"]
    await #expect(throws: LocalSyncConflict.self) {
      try await library.savePageMediums(
        pageID: "page", baseline: ["a"], selection: ["mine"], connected: true)
    }
    let attempt = try #require(library.mediumAttempts.first)
    #expect(attempt.state == .conflict)
    await #expect(throws: APIError.offline) {
      try await library.savePageMediums(
        pageID: "page", baseline: ["other-device"], selection: ["mine"], connected: false,
        replacing: attempt.id)
    }
    #expect(library.mediumAttempts.first == attempt)
    try await library.discardPageMediums(attempt.id)
    #expect(library.mediumAttempts.isEmpty)
    #expect(try await library.store.mediumAttempts(scope: library.scope).isEmpty)
    #expect(MediumSaveProtocol.bodies.count == 1)
    let page: ColoringPageRecord = try library.record(collection: "coloring_pages", id: "page")
    #expect(page.mediumIDs == ["other-device"])
  }

  @Test(.timeLimit(.minutes(1)), arguments: [401, 403], [false, true])
  func authenticationFailureClosesSessionAndKeepsDraft(status: Int, recovering: Bool) async throws {
    let library = try await makeLibrary(ids: ["a"])
    defer { library.onAuthenticationFailure = nil; library.pauseWrites() }
    if recovering {
      MediumSaveProtocol.failureAfterAcceptance = .networkConnectionLost
      await #expect(throws: APIError.self) {
        try await library.savePageMediums(
          pageID: "page", baseline: ["a"], selection: ["mine"], connected: true)
      }
    }
    var closed = false
    library.onAuthenticationFailure = {
      do {
        try await library.close(removingData: false)
        closed = true
      } catch { Issue.record("Session close failed") }
    }
    MediumSaveProtocol.overrideStatus = status
    await #expect(throws: status == 401 ? APIError.unauthenticated : .forbidden) {
      if recovering {
        let attempt = try #require(library.mediumAttempts.first)
        return try await library.resumePageMediums(attempt.id, connected: true)
      }
      return try await library.savePageMediums(
        pageID: "page", baseline: ["a"], selection: ["mine"], connected: true)
    }
    #expect(closed)
    #expect(library.items.isEmpty)
    let attempts = try await library.store.mediumAttempts(scope: library.scope)
    #expect(attempts.count == 1)
    #expect(attempts.first?.state == .awaitingReceipt)
    #expect(attempts.first?.patch.mediums == ["mine"])
  }

  @Test(arguments: [URLError.Code.networkConnectionLost, .cancelled])
  func ambiguousResultReplaysSameAttemptAndUsesCurrentRecord(code: URLError.Code) async throws {
    let library = try await makeLibrary(ids: ["a"])
    defer { library.pauseWrites() }
    MediumSaveProtocol.failureAfterAcceptance = code
    do {
      _ = try await library.savePageMediums(
        pageID: "page", baseline: ["a"], selection: ["mine"], connected: true)
      Issue.record("Expected response to be lost")
    } catch {}
    let attempt = try #require(library.mediumAttempts.first)
    #expect(attempt.state == .awaitingReceipt)
    #expect(library.pendingCount == 1)
    MediumSaveProtocol.page["mediums"] = ["later-device"]
    let saved = try await library.resumePageMediums(attempt.id, connected: true)
    #expect(saved.mediumIDs == ["later-device"])
    #expect(library.mediumAttempts.isEmpty)
    #expect(MediumSaveProtocol.bodies[0]["operationId"] as? String
      == MediumSaveProtocol.bodies[1]["operationId"] as? String)
    #expect(MediumSaveProtocol.bodies[1]["patch"] as? [String: [String]] == ["mediums": ["mine"]])
  }

  @Test
  func restartPreservesJournalAcrossMissingSnapshotAndAccountCleanup() async throws {
    let database = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
      .appending(path: "library.store")
    let scope = LocalAccountScope(backendURL: URL(string: "https://mediums.example.test")!, userID: "feature-user")
    let attempt = PageMediumAttempt(pageID: "page", baseline: ["b", "a"], selection: ["mine"])
    do {
      let store = try LocalLibraryStore(databaseURL: database)
      var page = featurePage("page", book: "book", number: 1)
      page.mediumIDs = ["b", "a"]
      try await store.ingestSnapshot(snapshot(page), scope: scope)
      try await store.saveMediumAttempt(attempt, scope: scope)
    }
    let store = try LocalLibraryStore(databaseURL: database)
    #expect(try await store.mediumAttempts(scope: scope) == [attempt])
    let otherAccount = LocalAccountScope(backendURL: scope.backendURL, userID: "another-user")
    let otherBackend = LocalAccountScope(backendURL: URL(string: "https://other.example.test")!, userID: scope.userID)
    #expect(try await store.mediumAttempts(scope: otherAccount).isEmpty)
    #expect(try await store.mediumAttempts(scope: otherBackend).isEmpty)
    try await store.ingestSnapshot(
      LocalFullSnapshot(version: 1, projects: [], coloringBooks: [], coloringPages: [],
        progressNotes: [], coloringPageProgressNotes: []), scope: scope)
    #expect(try await store.mediumAttempts(scope: scope) == [attempt])
    #expect(try await store.pendingCount(scope: scope) == 1)
    try await store.removeScope(scope)
    #expect(try await store.mediumAttempts(scope: scope).isEmpty)
  }

  @Test
  func offlineAndPendingEditsPreventNewAttempt() async throws {
    let library = try await makeLibrary(ids: ["a"])
    defer { library.pauseWrites() }
    await #expect(throws: APIError.offline) {
      try await library.savePageMediums(pageID: "page", baseline: ["a"], selection: [], connected: false)
    }
    #expect(library.mediumAttempts.isEmpty)
    _ = try await library.store.queueEdit(
      scope: library.scope, key: .init(kind: .page, id: "page"), patch: ["status": .string("in_progress")])
    await #expect(throws: LibrarySessionError.pendingChanges) {
      try await library.savePageMediums(pageID: "page", baseline: ["a"], selection: [], connected: true)
    }
    #expect(MediumSaveProtocol.bodies.isEmpty)
  }

  @Test
  func acceptedResponseCannotReportSuccessWhenLocalCommitFails() async throws {
    let library = try await makeLibrary(ids: ["a"])
    defer { library.pauseWrites() }
    MediumSaveProtocol.returnForeignBook = true
    await #expect(throws: PageMediumSaveError.recoveryRequired) {
      try await library.savePageMediums(pageID: "page", baseline: ["a"], selection: ["mine"], connected: true)
    }
    let attempt = try #require(library.mediumAttempts.first)
    #expect(attempt.state == .awaitingReceipt)
    MediumSaveProtocol.returnForeignBook = false
    _ = try await library.resumePageMediums(attempt.id, connected: true)
    #expect(library.mediumAttempts.isEmpty)
  }

  @Test(arguments: [400, 401, 404])
  func rejectedMissingAndAuthenticationResponsesKeepAttempt(status: Int) async throws {
    let library = try await makeLibrary(ids: ["a"])
    defer { library.pauseWrites() }
    MediumSaveProtocol.overrideStatus = status
    do {
      _ = try await library.savePageMediums(
        pageID: "page", baseline: ["a"], selection: ["foreign"], connected: true)
      Issue.record("Expected failure")
    } catch {}
    let attempt = try #require(library.mediumAttempts.first)
    #expect(attempt.state == (status == 400 ? .rejected : status == 404 ? .missing : .awaitingReceipt))
  }

  @Test
  func changedPayloadUUIDAndMalformedResponsesCannotBecomeSuccess() async throws {
    let library = try await makeLibrary(ids: ["a"])
    defer { library.pauseWrites() }
    let attempt = PageMediumAttempt(pageID: "page", baseline: ["a"], selection: ["mine"])
    _ = try await library.client.applyPageMediums(attempt: attempt)
    let changed = PageMediumAttempt(pageID: "page", baseline: ["a"], selection: [], id: attempt.id)
    await #expect(throws: PageMediumSaveError.integrityFailure) {
      try await library.client.applyPageMediums(attempt: changed)
    }
    MediumSaveProtocol.malformedResponse = true
    await #expect(throws: APIError.decoding) {
      try await library.savePageMediums(pageID: "page", baseline: ["mine"], selection: [], connected: true)
    }
    #expect(library.mediumAttempts.first?.state == .awaitingReceipt)
  }

  @Test
  func recoveryBlocksAnotherWriteAndKeepsUnknownLabels() async throws {
    let library = try await makeLibrary(ids: ["a"])
    defer { library.pauseWrites() }
    MediumSaveProtocol.failureAfterAcceptance = .networkConnectionLost
    do {
      _ = try await library.savePageMediums(pageID: "page", baseline: ["a"], selection: ["unknown"], connected: true)
    } catch {}
    await #expect(throws: PageMediumSaveError.recoveryRequired) {
      try await library.savePageMediums(pageID: "page", baseline: ["unknown"], selection: [], connected: true)
    }
    await #expect(throws: PageMediumSaveError.recoveryRequired) {
      let _: ColoringPageRecord = try await library.update(
        collection: "coloring_pages", id: "page", body: ["status": "completed"])
    }
    #expect(MediumNames.summary(ids: ["unknown", "a"], options: [.init(id: "a", name: "Pencils")])
      == "Pencils and 1 unavailable medium")
  }

  @Test
  func addingReceiptJournalOpensExistingLibraryStore() async throws {
    let database = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
      .appending(path: "library.store")
    try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
    let scope = LocalAccountScope(backendURL: URL(string: "https://mediums.example.test")!, userID: "feature-user")
    do {
      let schema = Schema([LocalStoredRecord.self, LocalStoredAccount.self, LocalStoredNote.self, LocalPendingRemoval.self])
      let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(
        "LocalLibrary", schema: schema, url: database, cloudKitDatabase: .none)])
      let context = ModelContext(container)
      let page = featurePage("page", book: "book", number: 1)
      context.insert(LocalStoredRecord(
        key: "\(scope.storageKey)|coloring_books|book", scope: scope.storageKey, kind: "coloring_books",
        recordID: "book", serverData: try JSONEncoder().encode(featureBook("book", title: "Book"))))
      context.insert(LocalStoredRecord(
        key: "\(scope.storageKey)|coloring_pages|page", scope: scope.storageKey, kind: "coloring_pages",
        recordID: "page", serverData: try JSONEncoder().encode(page), parentID: "book"))
      try context.save()
    }
    let store = try LocalLibraryStore(databaseURL: database)
    #expect(try await store.entries(scope: scope).count == 2)
    #expect(try await store.mediumAttempts(scope: scope).isEmpty)
    let attempt = PageMediumAttempt(pageID: "page", baseline: [], selection: ["mine"])
    try await store.saveMediumAttempt(attempt, scope: scope)
    #expect(try await store.mediumAttempts(scope: scope) == [attempt])
  }

  @Test
  func simultaneousSaveReservesPageBeforeItsFirstResponse() async throws {
    let library = try await makeLibrary(ids: ["a"])
    defer { library.pauseWrites() }
    let (events, continuation) = AsyncStream<Void>.makeStream()
    MediumSaveProtocol.applyStarted = continuation
    MediumSaveProtocol.holdApply = true
    let first = Task {
      try await library.savePageMediums(pageID: "page", baseline: ["a"], selection: ["mine"], connected: true)
    }
    for await _ in events { break }
    await #expect(throws: PageMediumSaveError.recoveryRequired) {
      try await library.savePageMediums(pageID: "page", baseline: ["a"], selection: [], connected: true)
    }
    MediumSaveProtocol.holdApply = false
    MediumSaveProtocol.suspendedRequest?.startLoading()
    _ = try await first.value
    #expect(library.mediumAttempts.isEmpty)
  }

  private func makeLibrary(ids: [String]) async throws -> LibrarySession {
    MediumSaveProtocol.reset(ids: ids)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MediumSaveProtocol.self]
    let keychain = KeychainSessionStore(service: "MediumSaveTests.\(UUID().uuidString)")
    let client = PocketBaseClient(baseURL: URL(string: "https://mediums.example.test")!,
      sessionStore: keychain, urlSession: URLSession(configuration: config))
    _ = try await client.signIn(identity: "example", password: "example")
    try keychain.clear()
    let library = LibrarySession(client: client, userID: "feature-user", store: try LocalLibraryStore.inMemory())
    var page = featurePage("page", book: "book", number: 1)
    page.mediumIDs = ids
    try await library.store.ingestSnapshot(snapshot(page), scope: library.scope)
    try await library.loadLocal()
    return library
  }

  private func snapshot(_ page: ColoringPageRecord) -> LocalFullSnapshot {
    LocalFullSnapshot(version: 1, projects: [], coloringBooks: [featureBook("book", title: "Book")],
      coloringPages: [page], progressNotes: [], coloringPageProgressNotes: [])
  }
}

private final class MediumSaveProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var page: [String: Any] = [:]
  nonisolated(unsafe) static var bodies: [[String: Any]] = []
  nonisolated(unsafe) static var receipts: [String: Data] = [:]
  nonisolated(unsafe) static var failureAfterAcceptance: URLError.Code?
  nonisolated(unsafe) static var overrideStatus: Int?
  nonisolated(unsafe) static var returnForeignBook = false
  nonisolated(unsafe) static var malformedResponse = false
  nonisolated(unsafe) static var holdApply = false
  nonisolated(unsafe) static var applyStarted: AsyncStream<Void>.Continuation?
  nonisolated(unsafe) static var suspendedRequest: MediumSaveProtocol?

  static func reset(ids: [String]) {
    page = ["id": "page", "book": "book", "page_number": 1, "status": "not_started",
      "photos": [], "mediums": ids, "created": "2026-09-01", "updated": "2026-09-01"]
    bodies = []; receipts = [:]; failureAfterAcceptance = nil
    overrideStatus = nil; returnForeignBook = false; malformedResponse = false
    holdApply = false; applyStarted = nil; suspendedRequest = nil
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  override func startLoading() {
    let path = request.url!.path
    if path.hasSuffix("auth-with-password") {
      respond(["token": "example-token", "record": ["id": "feature-user", "verified": true]])
    } else if path.hasSuffix("auth-refresh") {
      respond(["message": "Fictional authentication rejection"], status: 401)
    } else if path == "/api/mobile/sync/apply" {
      if Self.holdApply {
        Self.suspendedRequest = self
        Self.applyStarted?.yield(())
        Self.applyStarted?.finish()
        return
      }
      let data = bodyData
      let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
      Self.bodies.append(body)
      if let status = Self.overrideStatus {
        respond(["message": "Fictional failure"], status: status)
        return
      }
      let operationID = body["operationId"] as? String ?? ""
      let canonical = try! JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
      let replay = Self.receipts[operationID] != nil
      if let previous = Self.receipts[operationID], previous != canonical {
        respond(["reason": "operation_id_reused"], status: 409)
        return
      }
      let base = body["base"] as? [String: [String]] ?? [:]
      let patch = body["patch"] as? [String: [String]] ?? [:]
      if !replay {
        if base["mediums"] != Self.page["mediums"] as? [String] {
          respond(["reason": "field_conflict", "record": Self.page], status: 409)
          return
        }
        Self.page["mediums"] = patch["mediums"]
        Self.receipts[operationID] = canonical
      }
      if let error = Self.failureAfterAcceptance {
        Self.failureAfterAcceptance = nil
        client?.urlProtocol(self, didFailWithError: URLError(error))
        return
      }
      var record = Self.page
      if Self.returnForeignBook { record["book"] = "foreign-book" }
      respond(Self.malformedResponse ? ["outcome": "updated"]
        : ["outcome": replay ? "replayed" : "updated", "record": record])
    } else if path == "/api/mobile/sync/snapshot" {
      let book = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(featureBook("book", title: "Book")))
      respond(["version": 1, "projects": [], "coloringBooks": [book], "coloringPages": [Self.page],
        "progressNotes": [], "coloringPageProgressNotes": []])
    } else {
      respond(["message": "Unknown fixture"], status: 404)
    }
  }

  private func respond(_ object: [String: Any], status: Int = 200) {
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
      httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: object))
    client?.urlProtocolDidFinishLoading(self)
  }

  private var bodyData: Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while true {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { return result }
      result.append(buffer, count: count)
    }
  }
}
