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

  @Test func snapshotDeletionCapturesOnlyTheCommittedConflictTransition() async throws {
    let fixture = try await Fixture()
    try await fixture.seed()
    _ = try await fixture.library.store.queueEdit(
      scope: fixture.library.scope,
      key: LocalRecordKey(kind: .project, id: "project"),
      patch: ["title": .string("Private local title")])
    BehaviorProtocol.snapshot = Data(
      #"{"version":1,"projects":[],"coloringBooks":[],"coloringPages":[],"progressNotes":[],"coloringPageProgressNotes":[]}"#.utf8)

    try await fixture.coordinator.refresh()
    try await fixture.coordinator.refresh()

    #expect(fixture.events.names == [.syncConflict])
    #expect(fixture.events.properties.first?["record_type"] as? String == "projects")
    #expect(fixture.events.properties.first?["field_count"] as? Int == 1)
    #expect(fixture.events.properties.first?["record_id"] == nil)
    try await fixture.library.close(removingData: false)
  }

  @Test func acknowledgedFollowUpCapturesItsNewConflictOnce() async throws {
    let fixture = try await Fixture()
    try await fixture.seed()
    let key = LocalRecordKey(kind: .project, id: "project")
    _ = try await fixture.library.store.queueEdit(
      scope: fixture.library.scope, key: key,
      patch: ["title": .string("Private first title")])
    _ = try await fixture.library.store.queueEdit(
      scope: fixture.library.scope, key: key,
      patch: ["status": .string("progress")])
    BehaviorProtocol.record = try JSONEncoder().encode(featureProject(
      "project", title: "Private first title", status: "completed"))

    try await fixture.coordinator.syncPending()
    try await fixture.coordinator.syncPending()

    #expect(fixture.events.names == [.syncAccepted, .projectUpdated, .syncConflict])
    #expect(fixture.events.properties.last?["record_type"] as? String == "projects")
    #expect(fixture.events.properties.last?["field_count"] as? Int == 1)
    #expect(fixture.events.properties.last?["operation_id"] == nil)
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

  @Test func replacementLoadCompletesCancelledSearchCaptureOnce() async throws {
    let fixture = try await Fixture()
    try await fixture.seed()
    let gate = LoadGate()
    let model = LibraryModel(library: fixture.library, loadLocal: {
      try await gate.pause()
      try await fixture.library.loadLocal()
    })
    model.searchText = "Private"
    let submission = Task { await model.submitSearch() }
    await gate.waitUntilPaused(1)
    let replacement = Task { await model.load() }
    await gate.waitUntilPaused(2)

    submission.cancel()
    gate.resumeAll()
    await submission.value
    await replacement.value

    #expect(fixture.events.names == [.searchPerformed])
    #expect(fixture.events.properties.first?["result_count"] as? Int == 1)
    #expect(model.items.map(\.recordID) == ["project"])
    try await fixture.library.close(removingData: false)
  }

  @Test func supersededSearchPublishesOnlyLatestResultCount() async throws {
    let fixture = try await Fixture()
    try await fixture.seed()
    try await fixture.library.store.ingest(
      .diamond(featureProject("second", title: "Latest match")), scope: fixture.library.scope)
    let gate = LoadGate()
    let model = LibraryModel(library: fixture.library, loadLocal: {
      try await gate.pause()
      try await fixture.library.loadLocal()
    })
    model.searchText = "Private"
    let first = Task { await model.submitSearch() }
    await gate.waitUntilPaused(1)
    model.searchText = "Latest"
    let latest = Task { await model.submitSearch() }
    await gate.waitUntilPaused(2)

    gate.resumeAll()
    await first.value
    await latest.value

    #expect(fixture.events.names == [.searchPerformed])
    #expect(fixture.events.properties.first?["result_count"] as? Int == 1)
    #expect(model.items.map(\.recordID) == ["second"])
    try await fixture.library.close(removingData: false)
  }

  @Test func craftChangesCaptureOnlyExplicitChoices() async throws {
    let fixture = try await Fixture()
    let model = LibraryModel(library: fixture.library)
    model.select(.books)
    model.align(to: VerticalPreferences(diamondPainting: true, coloringBooks: false))
    model.apply(LibraryRequest(section: .books, status: BookStatus.inStash.rawValue))
    #expect(fixture.events.names.isEmpty)

    model.select(.diamonds, userInitiated: true)
    model.select(.books, userInitiated: true)
    #expect(fixture.events.names == [.craftChanged, .craftChanged])
    #expect(fixture.events.properties.map { $0["record_type"] as? String }
      == ["projects", "coloring_books"])
    try await fixture.library.close(removingData: false)
  }

  @Test func sidebarActionsDescribeOnlyExplicitCraftAndFilterChoices() {
    #expect(AppTab.craft(.diamonds).sidebarAnalytics(from: .home) == [
      SidebarAnalyticsAction(event: .craftChanged, recordType: "projects"),
    ])
    #expect(AppTab.shelf(.diamonds, status: "private-status")
      .sidebarAnalytics(from: .craft(.diamonds)) == [
        SidebarAnalyticsAction(event: .filterChanged, recordType: "projects", filterActive: true),
      ])
    #expect(AppTab.craft(.diamonds)
      .sidebarAnalytics(from: .shelf(.diamonds, status: "private-status")) == [
        SidebarAnalyticsAction(event: .filterChanged, recordType: "projects", filterActive: false),
      ])
    #expect(AppTab.library.sidebarAnalytics(from: .craft(.diamonds)).isEmpty)
  }

  @Test func notesFiltersCaptureInteractionsWithoutYearsOrAutomaticChanges() async throws {
    let fixture = try await Fixture()
    let filters = NotesFilterModel(library: fixture.library)
    filters.align(to: VerticalPreferences(diamondPainting: false, coloringBooks: true))
    filters.reconcile(availableYears: [2025])
    #expect(fixture.events.names.isEmpty)

    filters.selectCraft(.all)
    filters.selectYear(2026)
    filters.reconcile(availableYears: [2025])
    #expect(fixture.events.names == [.notesCraftFilterChanged, .notesYearFilterChanged])
    #expect(fixture.events.properties[0]["craft"] as? String == "all")
    #expect(fixture.events.properties[1]["filter_active"] as? Bool == true)
    #expect(fixture.events.properties.allSatisfy { $0["year"] == nil })
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
    #expect(fixture.events.names == [.projectCreated, .operationFailed])
    #expect(fixture.events.properties.last?["operation"] as? String == "create_record")
    #expect(fixture.events.properties.last?["failure_category"] as? String == "outcome_unknown")
    try await fixture.library.close(removingData: false)
  }

  @Test(arguments: ["projects", "progress_notes"])
  func failedPreparationCapturesOnceWithoutSendingWrite(collection: String) async throws {
    let fixture = try await Fixture()
    defer { fixture.analytics.close() }
    let gate = LoadGate()
    BehaviorProtocol.snapshotGate = gate
    BehaviorProtocol.status = 503
    let refresh = Task { try await fixture.library.refreshFromServer() }
    await gate.waitUntilPaused(1)
    var started = false
    let write = Task {
      started = true
      if collection == "projects" {
        let _: DiamondProjectRecord = try await fixture.library.create(
          collection: collection, body: ["title": "Private title"])
      } else {
        let _: DiamondProgressNoteRecord = try await fixture.library.create(
          collection: collection, multipart: PocketBaseMultipartForm(
            fields: ["project": "project", "content": "Private note"]))
      }
    }
    while !started { await Task.yield() }
    gate.resumeAll()
    do { try await refresh.value; Issue.record("Expected failed snapshot") }
    catch APIError.server {}
    do { try await write.value; Issue.record("Expected failed preparation") }
    catch APIError.server {}

    #expect(BehaviorProtocol.writeCount == 0)
    #expect(fixture.events.names == [.operationFailed])
    #expect(fixture.events.properties.first?["operation"] as? String
      == (collection == "projects" ? "create_record" : "add_note"))
    #expect(fixture.events.properties.first?["failure_category"] as? String == "outcome_unknown")
    let failure = try #require(fixture.events.properties.first)
    #expect(Set(failure.keys)
      == ["operation", "failure_category", "record_type"])
    await fixture.library.waitForWrites()
    try await fixture.library.close(removingData: false)
  }

  @Test(arguments: [LocalRecordKind.book, .page])
  func pendingChangesBlockPageCountWriteWithTypedFailure(kind: LocalRecordKind) async throws {
    let fixture = try await Fixture()
    defer { fixture.analytics.close() }
    let book = ColoringBookRecord(
      id: "book", user: "feature-user", title: "Private book", series: nil,
      status: "in_stash", totalPages: 2, completedPages: nil, completionPercentage: nil,
      coverImage: nil, publisher: nil, illustrator: nil,
      created: "2026-10-06", updated: "2026-10-06", expand: nil)
    let page = ColoringPageRecord(
      id: "page", book: "book", pageNumber: 1, status: "not_started", photos: [],
      revealedSubject: nil, completedAt: nil, startedAt: nil,
      created: "2026-10-06", updated: "2026-10-06", expand: nil)
    try await fixture.library.store.ingest(.book(book), scope: fixture.library.scope)
    try await fixture.library.store.ingest(.page(page), scope: fixture.library.scope)
    _ = try await fixture.library.store.queueEdit(
      scope: fixture.library.scope,
      key: LocalRecordKey(kind: kind, id: kind == .book ? "book" : "page"),
      patch: kind == .book ? ["title": .string("Private edited title")]
        : ["status": .string("in_progress")])
    BehaviorProtocol.status = 503

    do {
      let _: ColoringBookRecord = try await fixture.library.updateOnline(
        collection: "coloring_books", id: "book", body: ["total_pages": 3])
      Issue.record("Expected pending changes to block page count")
    } catch LibrarySessionError.pendingChanges {}

    #expect(BehaviorProtocol.writeCount == 0)
    #expect(fixture.events.names == [.operationFailed])
    #expect(fixture.events.properties.first?["operation"] as? String == "update_record")
    #expect(fixture.events.properties.first?["failure_category"] as? String == "pending_changes")
    #expect(fixture.events.properties.first?["record_type"] as? String == "coloring_books")
    #expect(try await fixture.library.store.pendingOperations(scope: fixture.library.scope).count == 1)
    await fixture.library.waitForWrites()
    try await fixture.library.close(removingData: false)
  }

  @Test func rejectedNoteEditCapturesTypedFailureWithoutPrivateData() async throws {
    let fixture = try await Fixture()
    try await fixture.seed()
    let note = DiamondProgressNoteRecord(
      id: "note", project: "project", content: "Private note", date: "2026-10-06",
      image: nil, created: "2026-10-06", updated: "2026-10-06", expand: nil)
    try await fixture.library.store.ingestNote(note, scope: fixture.library.scope)
    try await fixture.library.loadLocal()
    let model = LibraryItemDetailModel(
      item: .diamond(featureProject("project", title: "Private title")),
      library: fixture.library)
    #expect(await model.load())
    let loaded = try #require(model.progressNotes.first)
    BehaviorProtocol.status = 400

    let message = await model.updateProgressNote(
      loaded, content: "Private changed note", date: Date(timeIntervalSince1970: 0))

    #expect(message != nil)
    #expect(fixture.events.names == [.operationFailed])
    #expect(fixture.events.properties.first?["operation"] as? String == "edit_note")
    #expect(fixture.events.properties.first?["failure_category"] as? String == "validation")
    #expect(fixture.events.properties.first?["record_type"] as? String == "projects")
    #expect(fixture.events.properties.first?["content"] == nil)
    try await fixture.library.close(removingData: false)
  }

  @Test func cancelledWritesDoNotCaptureFailures() async throws {
    let fixture = try await Fixture()
    fixture.analytics.operationFailed(
      .editNote, collection: "progress_notes", error: APIError.cancelled,
      accountID: fixture.library.userID)
    fixture.analytics.operationFailed(
      .editNote, collection: "progress_notes", error: CancellationError(),
      accountID: fixture.library.userID)
    #expect(fixture.events.names.isEmpty)
    try await fixture.library.close(removingData: false)
  }

  @Test func craftingStreakSettingCapturesOnlyAnExplicitChange() async throws {
    let fixture = try await Fixture()
    var stored = false
    #expect(!AccountPreferenceInteraction.changed(from: stored, to: false))
    if AccountPreferenceInteraction.changed(from: stored, to: true) {
      stored = true
      fixture.library.captureAnalytics(
        .accountUpdated, properties: ["setting": "crafting_streak", "value": stored])
    }
    #expect(fixture.events.names == [.accountUpdated])
    #expect(fixture.events.properties.first?["setting"] as? String == "crafting_streak")
    #expect(fixture.events.properties.first?["value"] == nil)
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
    #expect(AnalyticsPayload.properties(["craft": "Private craft"],
      for: .notesCraftFilterChanged).isEmpty)
    #expect(AnalyticsPayload.properties(["filter_active": true, "year": 2026],
      for: .notesYearFilterChanged)["year"] == nil)
    #expect(AnalyticsPayload.properties(["surface": "private-filename.jpg"],
      for: .photoViewed).isEmpty)
    let photo = AnalyticsPayload.properties([
      "surface": AnalyticsPhotoSurface.notesFeed.rawValue,
      "filename": "private-filename.jpg",
      "record_id": "private-id",
    ], for: .photoViewed)
    #expect(photo["surface"] as? String == "notes_feed")
    #expect(Set(photo.keys) == ["surface"])
    let failure = AnalyticsPayload.properties([
      "operation": "edit_note", "failure_category": "permission",
      "record_type": "projects", "error": "Private validation message",
      "record_id": "private-id",
    ], for: .operationFailed)
    #expect(failure["operation"] as? String == "edit_note")
    #expect(failure["failure_category"] as? String == "permission")
    #expect(failure["record_type"] as? String == "projects")
    #expect(Set(failure.keys) == ["operation", "failure_category", "record_type"])
  }
}

@MainActor
private final class LoadGate {
  private var paused: [CheckedContinuation<Void, Never>] = []
  private var countWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

  func pause() async throws {
    await withCheckedContinuation { continuation in
      paused.append(continuation)
      resumeCountWaiters()
    }
    try Task.checkCancellation()
  }

  func waitUntilPaused(_ count: Int) async {
    if paused.count >= count { return }
    await withCheckedContinuation { continuation in
      countWaiters.append((count, continuation))
    }
  }

  func resumeAll() {
    let continuations = paused
    paused.removeAll()
    for continuation in continuations { continuation.resume() }
  }

  private func resumeCountWaiters() {
    let ready = countWaiters.filter { paused.count >= $0.count }
    countWaiters.removeAll { paused.count >= $0.count }
    for waiter in ready { waiter.continuation.resume() }
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
    BehaviorProtocol.snapshotGate = nil
    BehaviorProtocol.resetWriteCount()
    BehaviorProtocol.record = try JSONEncoder().encode(featureProject("project", title: "Private changed title", status: "progress"))
    BehaviorProtocol.snapshot = Data(
      #"{"version":1,"projects":[],"coloringBooks":[],"coloringPages":[],"progressNotes":[],"coloringPageProgressNotes":[]}"#.utf8)
  }

  func seed() async throws {
    try await library.store.ingest(.diamond(featureProject("project", title: "Private title")), scope: library.scope)
    try await library.loadLocal()
  }
}

private final class BehaviorProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var status = 200
  nonisolated(unsafe) static var record = Data()
  nonisolated(unsafe) static var snapshot = Data()
  nonisolated(unsafe) static var snapshotGate: LoadGate?
  private static let writeLock = NSLock()
  nonisolated(unsafe) private static var writes = 0
  static var writeCount: Int { writeLock.withLock { writes } }
  static func resetWriteCount() { writeLock.withLock { writes = 0 } }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    if request.url?.path == "/api/mobile/sync/snapshot", let gate = Self.snapshotGate {
      Task { @MainActor in
        try? await gate.pause()
        respond()
      }
    } else {
      respond()
    }
  }
  private func respond() {
    if request.url?.path.contains("/api/collections/") == true,
      ["POST", "PATCH", "DELETE"].contains(request.httpMethod) {
      Self.writeLock.withLock { Self.writes += 1 }
    }
    guard request.url?.path.contains("/apply") == true
      || request.url?.path == "/api/mobile/sync/snapshot"
      || ["POST", "PATCH", "DELETE"].contains(request.httpMethod)
      || request.url?.path.hasSuffix("auth-refresh") == true else {
      client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
      return
    }
    let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
    let body: Data
    if request.url?.path == "/api/mobile/sync/snapshot" {
      body = Self.snapshot
    } else if request.url?.path.contains("auth-with-password") == true || request.url?.path.hasSuffix("auth-refresh") == true {
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
