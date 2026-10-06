import Foundation
import PostHog
import Testing

@testable import OrganizedGlitter

@MainActor
@Suite(.serialized)
struct AnalyticsBehaviorTests {
  @Test func localSavePrecedesAcceptanceAndRetryDoesNotDuplicate() async throws {
    let fixture = try await Fixture()
    defer { fixture.analytics.close() }
    try await fixture.seed()
    let saved: DiamondProjectRecord = try await fixture.library.update(
      collection: "projects", id: "project", body: ["title": "Private changed title", "status": "progress"])
    #expect(saved.title == "Private changed title")
    #expect(fixture.events.names == [.recordSavedLocally])
    #expect(fixture.events.properties.first?["status_changed"] as? Bool == true)
    #expect(try await fixture.library.store.pendingOperations(scope: fixture.library.scope).count == 1)

    BehaviorProtocol.status = 503
    do { try await fixture.coordinator.syncPending(); Issue.record("Expected unavailable sync") }
    catch APIError.server {}
    #expect(fixture.events.names == [.recordSavedLocally])

    BehaviorProtocol.status = 200
    try await fixture.coordinator.syncPending()
    try await fixture.coordinator.syncPending()
    #expect(fixture.events.names == [.recordSavedLocally, .syncAccepted, .projectUpdated, .projectStatusChanged])
    #expect(try await fixture.library.store.pendingOperations(scope: fixture.library.scope).isEmpty)
    try await fixture.library.close(removingData: false)
  }

  @Test func failedLocalSaveAndDisabledAnalyticsLeaveLibraryUsable() async throws {
    let fixture = try await Fixture()
    try await fixture.seed()
    do {
      let _: DiamondProjectRecord = try await fixture.library.update(
        collection: "projects", id: "missing", body: ["title": "Private"])
      Issue.record("Expected missing record")
    } catch LocalLibraryError.missingRecord {}
    #expect(fixture.events.names.isEmpty)
    fixture.analytics.setSession(accountID: "feature-user", isActive: true, analyticsEnabled: false)
    let saved: DiamondProjectRecord = try await fixture.library.update(
      collection: "projects", id: "project", body: ["title": "Private changed title"])
    #expect(saved.title == "Private changed title")
    #expect(fixture.events.names.isEmpty)
    try await fixture.library.close(removingData: false)
  }

  @Test func conflictAndDurableResolutionAreNotAcceptedWrites() async throws {
    let fixture = try await Fixture()
    try await fixture.seed()
    let _: DiamondProjectRecord = try await fixture.library.update(
      collection: "projects", id: "project", body: ["title": "Private changed title"])
    BehaviorProtocol.status = 409
    try await fixture.coordinator.syncPending()
    try await fixture.coordinator.syncPending()
    try await fixture.library.loadLocal()
    #expect(fixture.events.names == [.recordSavedLocally, .syncConflict])
    let entry = try #require(fixture.library.conflicts.first)
    try await fixture.library.resolve(entry, retainLocal: false)
    try await fixture.library.resolve(entry, retainLocal: false)
    #expect(fixture.events.names == [.recordSavedLocally, .syncConflict, .conflictResolved])
    #expect(fixture.events.properties.last?["resolution"] as? String == "use_server")
    #expect(!fixture.events.names.contains(.projectUpdated))
    try await fixture.library.close(removingData: false)
  }

  @Test func keepingLocalConflictQueuesANewAcceptedOperation() async throws {
    let fixture = try await Fixture()
    try await fixture.seed()
    let _: DiamondProjectRecord = try await fixture.library.update(
      collection: "projects", id: "project", body: ["title": "Private changed title"])
    BehaviorProtocol.status = 409
    BehaviorProtocol.record = try JSONEncoder().encode(featureProject("project", title: "Private other title"))
    try await fixture.coordinator.syncPending()
    try await fixture.library.loadLocal()
    let entry = try #require(fixture.library.conflicts.first)
    try await fixture.library.resolve(entry, retainLocal: true)
    #expect(fixture.events.names == [.recordSavedLocally, .syncConflict, .conflictResolved])
    #expect(fixture.events.properties.last?["resolution"] as? String == "keep_local")
    #expect(try await fixture.library.store.pendingOperations(scope: fixture.library.scope).count == 1)
    BehaviorProtocol.status = 200
    BehaviorProtocol.record = try JSONEncoder().encode(featureProject("project", title: "Private changed title"))
    try await fixture.coordinator.syncPending()
    #expect(fixture.events.names.suffix(2) == [.syncAccepted, .projectUpdated])
    try await fixture.library.close(removingData: false)
  }

  @Test func rejectedSynchronizationRetainsEditsWithoutCountingAcceptance() async throws {
    let fixture = try await Fixture()
    try await fixture.seed()
    let _: DiamondProjectRecord = try await fixture.library.update(
      collection: "projects", id: "project", body: ["title": "Private changed title"])
    BehaviorProtocol.status = 400
    try await fixture.coordinator.syncPending()
    try await fixture.coordinator.syncPending()
    try await fixture.library.loadLocal()
    #expect(fixture.events.names == [.recordSavedLocally, .syncRejected])
    #expect(fixture.library.conflicts.first?.conflict == .rejectedByServer)
    #expect(fixture.library.items.first?.title == "Private changed title")
    try await fixture.library.close(removingData: false)
  }

  @Test func accountSwitchSuppressesOldSynchronization() async throws {
    let fixture = try await Fixture()
    try await fixture.seed()
    let _: DiamondProjectRecord = try await fixture.library.update(
      collection: "projects", id: "project", body: ["title": "Private changed title"])
    fixture.analytics.setSession(accountID: "other-account", isActive: true, analyticsEnabled: true)
    try await fixture.coordinator.syncPending()
    #expect(fixture.events.names == [.recordSavedLocally])
    try await fixture.library.close(removingData: false)
  }

  @Test func committedSearchOmitsQueryAndReloadDoesNotRepeatIt() async throws {
    let fixture = try await Fixture()
    try await fixture.seed()
    let model = LibraryModel(library: fixture.library)
    await model.load()
    model.searchText = "Private"
    #expect(fixture.events.names.isEmpty)
    await model.submitSearch()
    await model.load()
    #expect(fixture.events.names == [.searchPerformed])
    #expect(fixture.events.properties.first?["result_count"] as? Int == 1)
    model.sort = .titleAscending
    model.sort = .titleAscending
    model.statusFilter = "wishlist"
    #expect(fixture.events.names == [.searchPerformed, .sortChanged, .filterChanged])
    #expect(fixture.events.properties.allSatisfy { !$0.keys.contains("search") && !$0.keys.contains("title") })
    try await fixture.library.close(removingData: false)
  }

  @Test func acceptedOnlineCreateAndFailureHaveDistinctOutcomes() async throws {
    let fixture = try await Fixture()
    let _: DiamondProjectRecord = try await fixture.library.create(
      collection: "projects", body: ["title": "Private title"])
    #expect(fixture.events.names == [.projectCreated])
    BehaviorProtocol.status = 503
    do {
      let _: DiamondProjectRecord = try await fixture.library.create(
        collection: "projects", body: ["title": "Private title"])
      Issue.record("Expected rejected creation")
    } catch APIError.server {}
    #expect(fixture.events.names == [.projectCreated])
    try await fixture.library.close(removingData: false)
  }

  @Test func successfulLoginCountsOnceAndFailedLoginRemainsUntracked() async throws {
    let fixture = try await Fixture()
    let model = AppModel(client: fixture.library.client, sessionStore: fixture.sessionStore,
      themeStore: ThemeStore(), analytics: fixture.analytics)
    while model.phase == .restoring { await Task.yield() }
    BehaviorProtocol.status = 400
    await model.signIn(identity: "private@example.test", password: "private-password")
    #expect(fixture.events.names.isEmpty)
    BehaviorProtocol.status = 200
    await model.signIn(identity: "private@example.test", password: "private-password")
    #expect(fixture.events.names == [.appOpened, .loginSucceeded])
    #expect(fixture.events.properties.last?["auth_method"] as? String == "password")
    await model.restoreSession()
    #expect(fixture.events.names.filter { $0 == .loginSucceeded }.count == 1)
    try await model.library?.close(removingData: false)
    try fixture.sessionStore.clear()
  }

  @Test func acceptedNotesAndPhotosUseSafeOutcomeProperties() async throws {
    let fixture = try await Fixture()
    try await fixture.seed()
    let note: DiamondProgressNoteRecord = try await fixture.library.create(
      collection: "progress_notes", multipart: PocketBaseMultipartForm(
        fields: ["project": "project", "content": "Private note"],
        files: [PocketBaseMultipartFile(fieldName: "image", fileName: "private-name.jpg",
          contentType: "image/jpeg", data: Data([1]))]))
    #expect(note.id == "note")
    #expect(fixture.events.names == [.noteAdded])
    #expect(fixture.events.properties.last?["has_photo"] as? Bool == true)
    let _: DiamondProjectRecord = try await fixture.library.update(
      collection: "projects", id: "project", multipart: PocketBaseMultipartForm(files: [
        PocketBaseMultipartFile(fieldName: "image", fileName: "private-name.jpg",
          contentType: "image/jpeg", data: Data([1])),
      ]))
    #expect(fixture.events.names == [.noteAdded, .projectUpdated, .photoAdded])
    #expect(fixture.events.properties[1]["has_photo"] == nil)
    let _: DiamondProgressNoteRecord = try await fixture.library.updateOnline(
      collection: "progress_notes", id: note.id, body: ["content": "Private edited note"])
    try await fixture.library.delete(collection: "progress_notes", id: note.id)
    #expect(fixture.events.names.suffix(2) == [.noteUpdated, .noteDeleted])
    BehaviorProtocol.status = 503
    do {
      let _: DiamondProjectRecord = try await fixture.library.update(
        collection: "projects", id: "project", multipart: PocketBaseMultipartForm(files: [
          PocketBaseMultipartFile(fieldName: "image", fileName: "private-name.jpg",
            contentType: "image/jpeg", data: Data([1])),
        ]))
      Issue.record("Expected failed upload")
    } catch APIError.server {}
    #expect(fixture.events.names.filter { $0 == .photoAdded }.count == 1)
    #expect(fixture.events.properties.allSatisfy { !$0.keys.contains("content") && !$0.keys.contains("file_name") })
    try await fixture.library.close(removingData: false)
  }

  @Test func listWritesReuseWebOutcomesWithoutNames() async throws {
    let fixture = try await Fixture()
    BehaviorProtocol.record = Data(#"{"id":"entry","name":"Private artist name"}"#.utf8)
    let _: NamedRelationRecord = try await fixture.library.create(
      collection: "artists", body: ["name": "Private artist name"])
    let _: NamedRelationRecord = try await fixture.library.updateOnline(
      collection: "artists", id: "entry", body: ["name": "Private edited name"])
    try await fixture.library.delete(collection: "artists", id: "entry")
    #expect(fixture.events.names == [.artistCreated, .artistUpdated, .artistDeleted])
    #expect(fixture.events.properties.allSatisfy { $0["list_kind"] as? String == "artist" && $0["name"] == nil })
    try await fixture.library.close(removingData: false)
  }

  @Test func schemaRejectsPrivateStringsInvalidEnumsAndUnboundedCounts() throws {
    let sanitized = AnalyticsPayload.properties([
      "record_type": "private-title", "result_count": 10_001, "search": "Private query",
      "record_id": "private-id", "$set": ["name": "Private"],
    ], for: .searchPerformed)
    #expect(sanitized.isEmpty)
    #expect(AnalyticsPayload.properties(["result_count": true], for: .searchPerformed).isEmpty)
    #expect(AnalyticsPayload.properties(["result_count": 1.5], for: .searchPerformed).isEmpty)
    #expect(AnalyticsPayload.properties(["filter_active": 1], for: .filterChanged).isEmpty)
    #expect(AnalyticsPayload.properties(["result_count": NSNumber(value: 1)], for: .searchPerformed)["result_count"] as? Int == 1)
    #expect(AnalyticsPayload.properties(["result_count": -1], for: .searchPerformed).isEmpty)
    #expect(AnalyticsPayload.properties(["auth_provider": "private@example.test"], for: .loginSucceeded).isEmpty)
  }
}

@MainActor
private final class RecordedEvents {
  var names: [AnalyticsEvent] = []
  var properties: [[String: Any]] = []
  func capture(_ event: AnalyticsEvent, _ values: [String: Any]) {
    names.append(event)
    properties.append(values)
  }
}

@MainActor
private struct Fixture {
  let events = RecordedEvents()
  let analytics: NativeAnalytics
  let library: LibrarySession
  let coordinator: LocalSyncCoordinator
  let sessionStore: KeychainSessionStore

  init() async throws {
    analytics = NativeAnalytics(eventHandler: events.capture)
    analytics.setSession(accountID: "feature-user", isActive: true, analyticsEnabled: true)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [BehaviorProtocol.self]
    sessionStore = KeychainSessionStore(service: "AnalyticsBehavior.\(UUID().uuidString)")
    let client = PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: sessionStore,
      urlSession: URLSession(configuration: configuration))
    await client.prepareOfflineSession(StoredSession(token: "example-token", userID: "feature-user"))
    let store = try LocalLibraryStore.inMemory()
    library = LibrarySession(client: client, userID: "feature-user", store: store, analytics: analytics)
    coordinator = LocalSyncCoordinator(store: store, client: client, scope: library.scope, analytics: analytics)
    BehaviorProtocol.status = 200
    BehaviorProtocol.record = try JSONEncoder().encode(featureProject("project", title: "Private changed title", status: "progress"))
  }

  func seed() async throws {
    try await library.store.ingest(.diamond(featureProject("project", title: "Private title")), scope: library.scope)
    try await library.loadLocal()
  }
}

private final class BehaviorProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var status = 200
  nonisolated(unsafe) static var record = Data()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard request.url?.path.contains("/apply") == true || ["POST", "PATCH", "DELETE"].contains(request.httpMethod) || request.url?.path.hasSuffix("auth-refresh") == true else {
      client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
      return
    }
    let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
    let body: Data
    if request.url?.path.contains("auth-with-password") == true || request.url?.path.hasSuffix("auth-refresh") == true {
      body = Data(#"{"token":"example-token","record":{"id":"feature-user","verified":true,"analytics_opt_out":false}}"#.utf8)
    } else if request.url?.path.contains("progress_notes") == true {
      body = Data(#"{"id":"note","project":"project","user":"feature-user","content":"Private note","date":"2026-10-06","image":"private-name.jpg","created":"2026-10-06","updated":"2026-10-06"}"#.utf8)
    } else if request.url?.path.contains("/apply") == true {
      body = Data("{\"outcome\":\"updated\",\"reason\":\"field_conflict\",\"record\":".utf8) + Self.record + Data("}".utf8)
    } else { body = Self.record }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
