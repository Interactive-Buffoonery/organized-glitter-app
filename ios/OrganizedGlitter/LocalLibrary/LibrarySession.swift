import Foundation
import Observation
import Network

@MainActor
@Observable
final class LibrarySession {
  let analytics: NativeAnalytics?
  let client: PocketBaseClient
  let scope: LocalAccountScope
  let store: LocalLibraryStore
  private let coordinator: LocalSyncCoordinator
  private var syncTask: Task<Void, Error>?
  private var retryTask: Task<Void, Never>?
  private var retryAttempt = 0
  private var loadGeneration = 0
  private var historyLoadGeneration = 0
  private var historyRevision = 0
  private var acknowledgedSpins: [(revision: Int, record: SpinHistoryRecord)] = []
  private var active = true
  private var acceptsChanges = true
  private var onlineWrites = 0
  private var localWrites = 0
  private var writeWaiters: [CheckedContinuation<Void, Never>] = []
  private var onlineRecords: Set<LocalRecordKey> = []
  private var photoRecoveryRecords: Set<LocalRecordKey> = []

  private(set) var spinHistory: [SpinHistoryRecord] = []
  private(set) var spinHistoryLoadState = SpinHistoryLoadState.idle
  private var spinHistoryDraws: [(id: UUID, title: String)] = []
  private(set) var spinHistorySaveStates: [UUID: SpinHistorySaveState] = [:]
  private(set) var spinHistoryLimit = 8
  private(set) var spinHistoryTotal = 0
  private(set) var connectionAvailable: Bool?

  private(set) var items: [LibraryItem] = [] {
    didSet { rebuildShelfCounts() }
  }
  private var randomizerItemsByID: [LocalRecordKey: LibraryItem] = [:]
  private var randomizerCandidatesByMode: [RandomizerMode: [RandomizerCandidate]] = [:]
  private var bookTitles: [String: String] = [:]
  private var countsBySection: [LibrarySection: [String: Int]] = [:]
  private(set) var progressNotes: [DiamondProgressNoteRecord] = []
  private(set) var coloringPageProgressNotes: [ColoringProgressNoteRecord] = []
  private(set) var entries: [LocalLibraryEntry] = []
  private(set) var hasSnapshot = false
  private(set) var isSyncing = false
  private(set) var pendingCount = 0
  private(set) var generation = 0
  private(set) var syncMessage: String?
  var onAuthenticationFailure: (@MainActor () async -> Void)?

  var userID: String { scope.userID }
  var isActive: Bool { active }
  var conflicts: [LocalLibraryEntry] { entries.filter { $0.conflict != nil } }

  init(client: PocketBaseClient, userID: String, store: LocalLibraryStore,
    analytics: NativeAnalytics? = nil, connectionAvailable: Bool? = nil) {
    self.analytics = analytics
    self.connectionAvailable = connectionAvailable
    self.client = client
    self.scope = LocalAccountScope(backendURL: client.baseURL, userID: userID)
    self.store = store
    self.coordinator = LocalSyncCoordinator(store: store, client: client, scope: scope, analytics: analytics)
  }

  func captureAnalytics(_ event: AnalyticsEvent, properties: [String: Any] = [:]) {
    guard active else { return }
    analytics?.capture(event, properties: properties, accountID: userID)
  }

  func ownedBookTitles() -> [String: String] { bookTitles }

  func shelfCounts(for section: LibrarySection) -> [String: Int] {
    countsBySection[section] ?? [:]
  }

  private func rebuildShelfCounts() {
    var titles: [String: String] = [:]
    for item in items {
      if case .book(let book) = item, book.user == userID {
        titles[book.id] = book.title
      }
    }
    var counts: [LibrarySection: [String: Int]] = [:]
    for item in items {
      let section = item.section
      if item.belongs(to: section, userID: userID, bookTitles: titles) {
        counts[section, default: [:]][item.status, default: 0] += 1
      }
    }
    bookTitles = titles
    countsBySection = counts
  }

  private func rebuildRandomizerItems() {
    var owned: [LocalRecordKey: LibraryItem] = [:]
    let candidatesByMode = RandomizerCandidate.ownedByMode(entries: entries, userID: userID)
    for candidates in candidatesByMode.values {
      for candidate in candidates { owned[candidate.id] = candidate.item }
    }
    randomizerItemsByID = owned
    randomizerCandidatesByMode = candidatesByMode
  }

  func ownedRandomizerCandidates(mode: RandomizerMode) -> [RandomizerCandidate] {
    randomizerCandidatesByMode[mode] ?? []
  }

  func ownedRandomizerItem(id: LocalRecordKey, mode: RandomizerMode) -> LibraryItem? {
    guard let item = randomizerItemsByID[id], item.section == mode.section else { return nil }
    return item
  }

  func loadLocal() async throws {
    try checkActive()
    loadGeneration &+= 1
    let requestedGeneration = loadGeneration
    let projection = try await store.projection(scope: scope)
    let photoReviews = try await store.photoReviews(scope: scope)
    try checkActive()
    guard requestedGeneration == loadGeneration else { return }
    photoRecoveryRecords = photoReviews
    entries = projection.entries
    rebuildRandomizerItems()
    items = entries.map(\.item)
    progressNotes = projection.progressNotes
    coloringPageProgressNotes = projection.coloringPageProgressNotes
    hasSnapshot = projection.hasSnapshot
    pendingCount = projection.pendingCount
  }

  func refresh(force: Bool = false) async throws {
    do { try await refreshFromServer() }
    catch {
      if force || !hasSnapshot || error as? APIError == .unauthenticated
        || error as? APIError == .forbidden || error as? APIError == .cancelled
        || error is CancellationError { throw error }
    }
  }

  func refreshFromServer() async throws {
    try checkActive()
    guard onlineWrites == 0 else { throw LibrarySessionError.onlineWriteInProgress }
    if let syncTask { return try await syncTask.value }
    let task = Task { [weak self] in
      guard let self else { throw APIError.cancelled }
      let pending = self.pendingCount
      self.isSyncing = true
      defer { self.isSyncing = false }
      do {
        try await self.coordinator.refreshAndSync()
        try self.checkActive()
        try await self.loadLocal()
        try await self.client.retainDownloadedArtwork(
          items: self.entries.filter { $0.conflict != .deletedOnServer }.map(\.item),
          notes: self.progressNotes, coloringNotes: self.coloringPageProgressNotes, scope: self.scope)
        try self.checkActive()
        if pending > 0 {
          self.analytics?.capture(.syncCompleted,
            properties: ["pending_count": min(10_000, self.pendingCount)], accountID: self.userID)
        }
        self.syncMessage = nil
        self.generation &+= 1
        self.retryAttempt = 0
        self.retryTask?.cancel()
        self.retryTask = nil
        if self.hasQueuedChanges { self.scheduleSync(after: .seconds(10)) }
      } catch {
        guard self.active else { throw APIError.cancelled }
        try await self.loadLocal()
        if error as? APIError == .unauthenticated || error as? APIError == .forbidden {
          self.syncMessage = "Sign in again to synchronize your saved changes."
          Task { await self.onAuthenticationFailure?() }
          throw error
        }
        if error as? APIError == .cancelled || error is CancellationError { throw error }
        if pending > 0 {
          self.analytics?.capture(.syncFailed,
            properties: ["pending_count": min(10_000, self.pendingCount)], accountID: self.userID)
        }
        self.syncMessage = self.hasSnapshot
          ? "Showing your downloaded library. Changes will sync when the service is available."
          : "Connect to download your library."
        if self.hasQueuedChanges {
          self.retryAttempt = min(self.retryAttempt + 1, 5)
          let delay = min(15 * (1 << self.retryAttempt), 300)
          self.scheduleSync(after: .seconds(delay))
        }
        throw error
      }
    }
    syncTask = task
    defer { syncTask = nil }
    try await task.value
  }

  private var hasQueuedChanges: Bool {
    entries.contains { $0.pending && $0.conflict == nil }
  }

  private func scheduleSync(after delay: Duration = .seconds(1)) {
    guard active, retryTask == nil else { return }
    retryTask = Task { [weak self] in
      do { try await Task.sleep(for: delay) } catch { return }
      guard let self, self.active, !Task.isCancelled else { return }
      self.retryTask = nil
      try? await self.refreshFromServer()
    }
  }

  func monitorConnectivity() async {
    let monitor = NWPathMonitor()
    let updates = AsyncStream<Bool> { continuation in
      monitor.pathUpdateHandler = { path in continuation.yield(path.status == .satisfied) }
      continuation.onTermination = { _ in monitor.cancel() }
      monitor.start(queue: DispatchQueue(label: "OrganizedGlitter.connectivity"))
    }
    defer { monitor.cancel() }
    for await connected in updates {
      guard active, !Task.isCancelled else { return }
      connectionAvailable = connected
      if connected { try? await refresh() }
    }
  }

  func update<Record: Codable & Sendable>(
    collection: String, id: String, body: some Encodable & Sendable
  ) async throws -> Record {
    try checkWritable()
    guard let kind = LocalRecordKind(rawValue: collection) else {
      throw LocalLibraryError.unsupportedField
    }
    let key = LocalRecordKey(kind: kind, id: id)
    guard !onlineRecords.contains(key) else { throw LibrarySessionError.pendingChanges }
    guard !photoRecoveryRecords.contains(key) else { throw LibrarySessionError.photoActionNeedsReview }
    let patch = try JSONDecoder().decode(
      [String: LocalJSONValue].self, from: JSONEncoder().encode(body))
    if patch.isEmpty { return try record(collection: collection, id: id) }
    let previousStatus = items.first { $0.localRecordKey == key }?.status
    localWrites += 1
    defer { localWrites -= 1; resumeWriteWaitersIfIdle() }
    let entry = try await store.queueEdit(
      scope: scope, key: LocalRecordKey(kind: kind, id: id), patch: patch)
    try checkActive()
    loadGeneration &+= 1
    if let index = entries.firstIndex(where: { $0.item.localRecordKey == key }) {
      entries[index] = entry
    } else { entries.append(entry) }
    rebuildRandomizerItems()
    items = entries.map(\.item)
    pendingCount = entries.filter(\.pending).count
    generation &+= 1
    analytics?.capture(.recordSavedLocally, properties: [
      "record_type": collection, "field_count": patch.count,
      "status_changed": patch["status"].map { $0 != previousStatus.map(LocalJSONValue.string) } ?? false,
    ], accountID: userID)
    scheduleSync()
    return try Self.decode(entry.item)
  }

  func record<Record: Codable & Sendable>(collection: String, id: String) throws -> Record {
    try checkActive()
    guard let item = items.first(where: {
      $0.localRecordKey.kind.rawValue == collection && $0.recordID == id
    }) else { throw LocalLibraryError.missingRecord }
    return try Self.decode(item)
  }

  func create<Record: Decodable & Sendable>(
    collection: String, body: some Encodable & Sendable
  ) async throws -> Record {
    var beganWrite = false
    defer { if beganWrite { endOnlineWrite() } }
    let saved: Record
    do {
      try await beginOnlineWrite()
      beganWrite = true
      saved = try await client.create(collection: collection, body: body)
    } catch {
      captureOnlineFailure(error, operation: createOperation(collection), collection: collection)
      throw error
    }
    try checkActive()
    try await acceptOnline(saved)
    analytics?.record(.created, collection: collection, accountID: userID)
    return saved
  }

  func create<Record: Decodable & Sendable>(
    collection: String, multipart: PocketBaseMultipartForm
  ) async throws -> Record {
    var beganWrite = false
    defer { if beganWrite { endOnlineWrite() } }
    let saved: Record
    do {
      try await beginOnlineWrite()
      beganWrite = true
      saved = try await client.create(collection: collection, multipart: multipart)
    } catch {
      captureOnlineFailure(error, operation: createOperation(collection), collection: collection)
      throw error
    }
    try checkActive()
    try await acceptOnline(saved)
    analytics?.record(.created, collection: collection, hasPhoto: !multipart.files.isEmpty, accountID: userID)
    return saved
  }

  func updateOnline<Record: Decodable & Sendable>(
    collection: String, id: String, body: some Encodable & Sendable
  ) async throws -> Record {
    var beganWrite = false
    defer { if beganWrite { endOnlineWrite() } }
    var reserved: Set<LocalRecordKey> = []
    defer { onlineRecords.subtract(reserved) }
    let previousStatus: String?
    let patch: [String: LocalJSONValue]
    let saved: Record
    do {
      try await beginOnlineWrite()
      beganWrite = true
      reserved = try await reserveOnlineRecord(collection: collection, id: id)
      previousStatus = items.first { $0.localRecordKey.kind.rawValue == collection && $0.recordID == id }?.status
      patch = (try? JSONDecoder().decode([String: LocalJSONValue].self, from: JSONEncoder().encode(body))) ?? [:]
      saved = try await client.update(collection: collection, id: id, body: body)
    } catch {
      captureOnlineFailure(error, operation: updateOperation(collection), collection: collection)
      throw error
    }
    try checkActive()
    try await acceptOnline(saved)
    analytics?.record(.updated, collection: collection, accountID: userID)
    if case .string(let status) = patch["status"], status != previousStatus {
      analytics?.record(.statusChanged, collection: collection, accountID: userID)
    }
    return saved
  }

  func photoReviewRequired(id: String) -> Bool {
    photoRecoveryRecords.contains(LocalRecordKey(kind: .page, id: id))
  }

  func requirePhotoReview(id: String) async throws {
    try checkActive()
    localWrites += 1
    defer { localWrites -= 1; resumeWriteWaitersIfIdle() }
    try await store.setPhotoReview(id: id, required: true, scope: scope)
    loadGeneration &+= 1
    photoRecoveryRecords.insert(LocalRecordKey(kind: .page, id: id))
  }

  func finishPhotoReview(id: String) async throws {
    try checkActive()
    localWrites += 1
    defer { localWrites -= 1; resumeWriteWaitersIfIdle() }
    try await store.setPhotoReview(id: id, required: false, scope: scope)
    loadGeneration &+= 1
    photoRecoveryRecords.remove(LocalRecordKey(kind: .page, id: id))
  }

  func changePagePhoto(id: String, filename: String, setMain: Bool) async throws -> ColoringPageRecord {
    var markedForReview = false
    var serverAccepted = false
    do {
      guard await client.isAuthenticated(as: userID) else { throw APIError.cancelled }
      try await beginOnlineWrite()
      defer {
        endOnlineWrite(refreshLibrary: false)
        if hasQueuedChanges { scheduleSync() }
      }
      let reserved = try await reserveOnlineRecord(collection: "coloring_pages", id: id)
      defer { onlineRecords.subtract(reserved) }
      guard localWrites == 0 else { throw LibrarySessionError.pendingChanges }
      let current: ColoringPageRecord = try record(collection: "coloring_pages", id: id)
      guard current.photos.contains(filename) else { throw APIError.conflict }
      try await requirePhotoReview(id: id)
      markedForReview = true
      let saved: ColoringPageRecord
      if setMain {
        saved = try await client.setMainPagePhoto(pageID: id, filename: filename, userID: userID)
      } else {
        saved = try await client.removePagePhoto(pageID: id, filename: filename, userID: userID)
      }
      try checkActive()
      guard await client.isAuthenticated(as: userID) else { throw APIError.cancelled }
      guard saved.id == current.id, saved.book == current.book else { throw APIError.decoding }
      serverAccepted = true
      captureAnalytics(setMain ? .pageMainPhotoChanged : .pagePhotoDeleted,
        properties: ["record_type": "coloring_pages", "save_destination": "server"])
      try await acceptPagePhoto(saved, replacing: current)
      try await finishPhotoReview(id: id)
      return saved
    } catch {
      if markedForReview {
        switch error as? APIError {
        case .validation, .conflict, .forbidden, .unauthenticated, .emailUnverified, .notFound:
          try? await finishPhotoReview(id: id)
        default: break
        }
      }
      if !serverAccepted {
        captureOnlineFailure(error, operation: setMain ? .setMainPhoto : .deletePhoto,
          collection: "coloring_pages")
      }
      await recoverHistoryAuthentication(after: error)
      throw error
    }
  }

  func appendPagePhoto(id: String, multipart: PocketBaseMultipartForm) async throws -> ColoringPageRecord {
    var markedForReview = false
    var serverAccepted = false
    do {
      guard await client.isAuthenticated(as: userID) else { throw APIError.cancelled }
      try await beginOnlineWrite()
      defer {
        endOnlineWrite(refreshLibrary: false)
        if hasQueuedChanges { scheduleSync() }
      }
      let reserved = try await reserveOnlineRecord(collection: "coloring_pages", id: id)
      defer { onlineRecords.subtract(reserved) }
      guard localWrites == 0 else { throw LibrarySessionError.pendingChanges }
      let current: ColoringPageRecord = try record(collection: "coloring_pages", id: id)
      try await requirePhotoReview(id: id)
      markedForReview = true
      let saved: ColoringPageRecord = try await client.update(collection: "coloring_pages", id: id, multipart: multipart)
      try checkActive()
      guard await client.isAuthenticated(as: userID) else { throw APIError.cancelled }
      guard saved.id == current.id, saved.book == current.book else { throw APIError.decoding }
      serverAccepted = true
      analytics?.record(.updated, collection: "coloring_pages", accountID: userID)
      if !multipart.files.isEmpty {
        analytics?.capture(.pagePhotoAdded,
          properties: ["record_type": "coloring_pages", "save_destination": "server"], accountID: userID)
      }
      try await acceptPagePhoto(saved, replacing: current)
      try await finishPhotoReview(id: id)
      return saved
    } catch {
      if markedForReview {
        switch error as? APIError {
        case .validation, .conflict, .forbidden, .unauthenticated, .emailUnverified, .notFound:
          try? await finishPhotoReview(id: id)
        default: break
        }
      }
      if !serverAccepted {
        captureOnlineFailure(error, operation: .addPhoto, collection: "coloring_pages")
      }
      await recoverHistoryAuthentication(after: error)
      throw error
    }
  }

  private func acceptPagePhoto(_ saved: ColoringPageRecord, replacing current: ColoringPageRecord) async throws {
    try checkActive()
    guard await client.isAuthenticated(as: userID) else { throw APIError.cancelled }
    guard saved.id == current.id, saved.book == current.book else { throw APIError.decoding }
    do {
      try await store.ingest(.page(saved), scope: scope)
      try checkActive()
      try await loadLocal()
      generation &+= 1
    } catch {
      throw APIError.server
    }
  }

  func refreshPagePhotos() async throws {
    do {
      try checkActive()
      guard await client.isAuthenticated(as: userID) else { throw APIError.cancelled }
      try await beginOnlineWrite()
      defer {
        endOnlineWrite(refreshLibrary: false)
        if hasQueuedChanges { scheduleSync() }
      }
      let snapshot = try await client.mobileSnapshot(userID: userID)
      try checkActive()
      guard await client.isAuthenticated(as: userID) else { throw APIError.cancelled }
      let transitions = try await store.ingestSnapshot(snapshot, scope: scope)
      for transition in transitions {
        analytics?.capture(.syncConflict, properties: [
          "record_type": transition.key.kind.rawValue,
          "field_count": min(10_000, transition.fieldCount),
        ], accountID: userID)
      }
      try checkActive()
      try await loadLocal()
      try await client.retainDownloadedArtwork(
        items: entries.filter { $0.conflict != .deletedOnServer }.map(\.item),
        notes: progressNotes, coloringNotes: coloringPageProgressNotes, scope: scope)
      try checkActive()
      generation &+= 1
    } catch {
      await recoverHistoryAuthentication(after: error)
      throw error
    }
  }

  func update<Record: Decodable & Sendable>(
    collection: String, id: String, multipart: PocketBaseMultipartForm
  ) async throws -> Record {
    var beganWrite = false
    defer { if beganWrite { endOnlineWrite() } }
    var reserved: Set<LocalRecordKey> = []
    defer { onlineRecords.subtract(reserved) }
    let saved: Record
    do {
      try await beginOnlineWrite()
      beganWrite = true
      reserved = try await reserveOnlineRecord(collection: collection, id: id)
      saved = try await client.update(collection: collection, id: id, multipart: multipart)
    } catch {
      captureOnlineFailure(error, operation: .addPhoto, collection: collection)
      throw error
    }
    try checkActive()
    try await acceptOnline(saved)
    analytics?.record(.updated, collection: collection, accountID: userID)
    if !multipart.files.isEmpty {
      analytics?.capture(collection == "coloring_pages" ? .pagePhotoAdded : .photoAdded,
        properties: ["record_type": collection, "save_destination": "server"], accountID: userID)
    }
    return saved
  }

  func delete(collection: String, id: String) async throws {
    var beganWrite = false
    defer { if beganWrite { endOnlineWrite() } }
    var reserved: Set<LocalRecordKey> = []
    defer { onlineRecords.subtract(reserved) }
    do {
      try await beginOnlineWrite()
      beganWrite = true
      reserved = try await reserveOnlineRecord(collection: collection, id: id)
      try await client.delete(collection: collection, id: id)
    } catch {
      captureOnlineFailure(error, operation: deleteOperation(collection), collection: collection)
      throw error
    }
    try checkActive()
    analytics?.record(.deleted, collection: collection, accountID: userID)
    let noteKind: LocalNoteKind?
    switch collection {
    case "progress_notes": noteKind = .diamond
    case "coloring_page_progress_notes": noteKind = .coloring
    default: noteKind = nil
    }
    if let kind = LocalRecordKind(rawValue: collection) {
      do {
        try await store.removeConfirmed(scope: scope, key: LocalRecordKey(kind: kind, id: id))
        try await loadLocal()
        generation &+= 1
      } catch { syncMessage = "Removed from your account. Refresh to update this device." }
    } else if let noteKind {
      do {
        try await store.removeNote(kind: noteKind, id: id, scope: scope)
        try await loadLocal()
        generation &+= 1
      } catch { syncMessage = "Removed from your account. Refresh to update this device." }
    }
    Task { try? await refresh(force: true) }
  }

  func resolve(_ entry: LocalLibraryEntry, retainLocal: Bool) async throws {
    try checkWritable()
    guard try await store.entry(scope: scope, key: entry.item.localRecordKey)?.conflict != nil else { return }
    try checkWritable()
    localWrites += 1
    defer { localWrites -= 1; resumeWriteWaitersIfIdle() }
    _ = try await store.resolveConflict(
      scope: scope, key: entry.item.localRecordKey, retainLocal: retainLocal)
    try await loadLocal()
    generation &+= 1
    analytics?.capture(.conflictResolved, properties: [
      "record_type": entry.item.localRecordKey.kind.rawValue,
      "resolution": retainLocal ? "keep_local" : "use_server",
    ], accountID: userID)
    Task { try? await refresh(force: true) }
  }

  private func createOperation(_ collection: String) -> AnalyticsOperation {
    ["progress_notes", "coloring_page_progress_notes"].contains(collection)
      ? .addNote : .createRecord
  }

  private func updateOperation(_ collection: String) -> AnalyticsOperation {
    ["progress_notes", "coloring_page_progress_notes"].contains(collection)
      ? .editNote : .updateRecord
  }

  private func deleteOperation(_ collection: String) -> AnalyticsOperation {
    ["progress_notes", "coloring_page_progress_notes"].contains(collection)
      ? .deleteNote : .deleteRecord
  }

  private func captureOnlineFailure(
    _ error: Error, operation: AnalyticsOperation, collection: String
  ) {
    guard active, !Task.isCancelled else { return }
    analytics?.operationFailed(operation, collection: collection, error: error, accountID: userID)
  }

  func loadSpinHistory(limit: Int? = nil) async {
    await refreshSpinHistory(limit: limit)
  }

  private func refreshSpinHistory(limit: Int? = nil, preserving saved: SpinHistoryRecord? = nil) async {
    guard active, !Task.isCancelled else { return }
    historyLoadGeneration &+= 1
    let generation = historyLoadGeneration
    let revision = historyRevision
    spinHistoryLimit = limit == 50 ? 50 : (limit == nil ? spinHistoryLimit : 8)
    let requestedLimit = spinHistoryLimit
    spinHistoryLoadState = .loading
    do {
      let page: RecordList<SpinHistoryRecord> = try await client.list(
        collection: "randomizer_spins", perPage: requestedLimit,
        filter: PocketBaseFilter.equals(.user, userID), sort: "-spun_at")
      try checkActive()
      guard generation == historyLoadGeneration else { return }
      let returned = page.items.filter { $0.user == userID }
      let concurrent = acknowledgedSpins.filter { $0.revision > revision }.map(\.record)
      spinHistory = Self.sortedSpins(returned + concurrent + (saved.map { [$0] } ?? []), limit: requestedLimit)
      spinHistoryTotal = max(page.totalItems, spinHistory.count)
      spinHistoryLoadState = .loaded
    } catch {
      guard active, generation == historyLoadGeneration else { return }
      if Task.isCancelled { spinHistoryLoadState = .idle }
      else {
        spinHistoryLoadState = .failed
        await recoverHistoryAuthentication(after: error)
      }
    }
  }

  func spinHistoryFailures(excluding selectionID: UUID? = nil) -> [SpinHistoryFailure] {
    spinHistoryDraws.compactMap { draw in
      guard draw.id != selectionID, let state = spinHistorySaveStates[draw.id],
        state.failureAnnouncement != nil else { return nil }
      return SpinHistoryFailure(id: draw.id, title: draw.title, state: state)
    }
  }

  @discardableResult
  func recordSpin(selection: RandomizerSelection, completedAt: Date) async -> SpinHistorySaveState {
    guard selection.scope == scope, active else { return .rejected }
    if let state = spinHistorySaveStates[selection.id] { return state }
    spinHistoryDraws.append((selection.id, selection.winner.title))
    spinHistorySaveStates[selection.id] = .saving
    guard !Task.isCancelled, acceptsChanges else {
      spinHistorySaveStates[selection.id] = .rejected
      return .rejected
    }
    guard connectionAvailable != false else {
      spinHistorySaveStates[selection.id] = .notSent
      return .notSent
    }
    let ownsSnapshot = !selection.candidates.isEmpty
      && selection.candidates.contains(selection.winner)
      && selection.candidates.allSatisfy {
        $0.item.belongs(to: selection.mode.section, userID: userID, bookTitles: ownedBookTitles())
      }
    let body = SpinHistoryCreate(selection: selection, userID: userID, completedAt: completedAt)
    guard ownsSnapshot, !body.projectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      randomizerTarget(id: selection.winner.id, mode: selection.mode,
        verticals: VerticalPreferences(diamondPainting: true, coloringBooks: true)) != nil else {
      spinHistorySaveStates[selection.id] = .rejected
      return .rejected
    }
    var dispatched = false
    let savedState: SpinHistorySaveState
    let acknowledgement: SpinHistoryRecord
    do {
      try await beginOnlineWrite()
      defer { endOnlineWrite(refreshLibrary: false) }
      guard connectionAvailable != false else {
        spinHistorySaveStates[selection.id] = .notSent
        return .notSent
      }
      dispatched = true
      let saved: SpinHistoryRecord = try await client.create(collection: "randomizer_spins", body: body,
        canRefreshAuthentication: false)
      guard active else { return .unknown }
      guard saved.user == userID else { throw APIError.decoding }
      historyRevision &+= 1
      acknowledgedSpins.append((historyRevision, saved))
      if acknowledgedSpins.count > 50 { acknowledgedSpins.removeFirst(acknowledgedSpins.count - 50) }
      if !spinHistory.contains(where: { $0.id == saved.id }) { spinHistoryTotal += 1 }
      spinHistory = Self.sortedSpins([saved] + spinHistory, limit: spinHistoryLimit)
      let state = SpinHistorySaveState.saved(saved.id)
      spinHistorySaveStates[selection.id] = state
      savedState = state
      acknowledgement = saved
    } catch {
      guard active else { return .unknown }
      let state: SpinHistorySaveState
      if !dispatched { state = (error as? APIError) == .offline ? .notSent : .rejected }
      else {
        switch error as? APIError {
        case .unauthenticated, .emailUnverified, .forbidden, .conflict, .validation, .notFound:
          state = .rejected
        default: state = .unknown
        }
      }
      spinHistorySaveStates[selection.id] = state
      await recoverHistoryAuthentication(after: error)
      if active, state == .unknown { Task { await self.loadSpinHistory() } }
      return state
    }
    await refreshSpinHistory(preserving: acknowledgement)
    return savedState
  }

  private func recoverHistoryAuthentication(after error: Error) async {
    guard !Task.isCancelled, let error = error as? APIError,
      error == .unauthenticated || error == .forbidden else { return }
    await onAuthenticationFailure?()
  }

  func spinHistoryTarget(_ spin: SpinHistoryRecord, verticals: VerticalPreferences) -> LibraryItem? {
    guard spin.user == userID, let target = spin.target else { return nil }
    let kind: LocalRecordKind
    switch target.mode {
    case .diamond: kind = .project
    case .book: kind = .book
    case .page: kind = .page
    }
    return randomizerTarget(id: LocalRecordKey(kind: kind, id: target.id),
      mode: target.mode, verticals: verticals)
  }

  private static func sortedSpins(_ records: [SpinHistoryRecord], limit: Int) -> [SpinHistoryRecord] {
    var seen: Set<String> = []
    return records.filter { seen.insert($0.id).inserted }.sorted {
      $0.spunAt == $1.spunAt ? $0.id > $1.id : $0.spunAt > $1.spunAt
    }.prefix(limit).map { $0 }

  }

  func pauseWrites() { acceptsChanges = false }
  func resumeWrites() { if active { acceptsChanges = true } }

  func waitForWrites() async {
    guard localWrites > 0 || onlineWrites > 0 else { return }
    await withCheckedContinuation { writeWaiters.append($0) }
  }

  private func resumeWriteWaitersIfIdle() {
    guard localWrites == 0, onlineWrites == 0 else { return }
    let waiters = writeWaiters
    writeWaiters = []
    for waiter in waiters { waiter.resume() }
  }

  func close(removingData: Bool) async throws {
    pauseWrites()
    await waitForWrites()
    if removingData { try await store.beginRemoval(scope: scope) }
    active = false
    loadGeneration &+= 1
    retryTask?.cancel()
    retryTask = nil
    syncTask?.cancel()
    await coordinator.cancel()
    if let task = syncTask { _ = await task.result }
    syncTask = nil
    historyLoadGeneration &+= 1
    spinHistory = []
    spinHistorySaveStates = [:]
    spinHistoryDraws = []
    acknowledgedSpins = []
    spinHistoryLoadState = .idle
    spinHistoryTotal = 0
    items = []
    randomizerItemsByID = [:]
    randomizerCandidatesByMode = [:]
    entries = []
    progressNotes = []
    coloringPageProgressNotes = []
    if removingData {
      try await store.removeScope(scope)
      try await client.removeDownloadedArtwork(scope: scope)
      try await store.finishRemoval(scope: scope)
    }
  }

  private func beginOnlineWrite() async throws {
    try checkWritable()
    onlineWrites += 1
    do {
      if let syncTask { try await syncTask.value }
      try checkWritable()
    } catch {
      onlineWrites -= 1
      resumeWriteWaitersIfIdle()
      throw error
    }
  }

  private func endOnlineWrite(refreshLibrary: Bool = true) {
    onlineWrites -= 1
    resumeWriteWaitersIfIdle()
    if refreshLibrary, onlineWrites == 0, active { Task { try? await refresh(force: true) } }
  }

  private func reserveOnlineRecord(collection: String, id: String) async throws -> Set<LocalRecordKey> {
    try checkWritable()
    try await loadLocal()
    try checkWritable()
    let affected = entries.filter {
      if $0.item.localRecordKey.kind.rawValue == collection && $0.item.recordID == id { return true }
      if collection == "coloring_books", case .page(let page) = $0.item { return page.book == id }
      return false
    }
    let keys = Set(affected.map { $0.item.localRecordKey })
    guard affected.allSatisfy({ !$0.pending }), keys.isDisjoint(with: onlineRecords) else {
      throw LibrarySessionError.pendingChanges
    }
    guard keys.isDisjoint(with: photoRecoveryRecords) else { throw LibrarySessionError.photoActionNeedsReview }
    onlineRecords.formUnion(keys)
    return keys
  }

  private func acceptOnline<Record>(_ saved: Record) async throws {
    let item: LibraryItem?
    switch saved {
    case let value as DiamondProjectRecord: item = .diamond(value)
    case let value as ColoringBookRecord: item = .book(value)
    case let value as ColoringPageRecord: item = .page(value)
    default: item = nil
    }
    do {
      if let item { try await store.ingest(item, scope: scope) }
      else if let note = saved as? DiamondProgressNoteRecord {
        try await store.ingestNote(note, scope: scope)
      } else if let note = saved as? ColoringProgressNoteRecord {
        try await store.ingestNote(note, scope: scope)
      }
      try checkActive()
      try await loadLocal()
      generation &+= 1
    } catch {
      // The server accepted the write. Retrying it could duplicate a creation.
      syncMessage = "Saved to your account. Refresh to update this device."
    }
    Task { try? await refresh(force: true) }
  }

  private func checkWritable() throws {
    try checkActive()
    guard acceptsChanges else { throw APIError.cancelled }
  }

  private func checkActive() throws {
    guard active, !Task.isCancelled else { throw APIError.cancelled }
  }

  private static func decode<Record: Decodable>(_ item: LibraryItem) throws -> Record {
    let data: Data
    switch item {
    case .diamond(let record): data = try JSONEncoder().encode(record)
    case .book(let record): data = try JSONEncoder().encode(record)
    case .page(let record): data = try JSONEncoder().encode(record)
    }
    return try JSONDecoder().decode(Record.self, from: data)
  }
}

enum LibrarySessionError: LocalizedError {
  case pendingChanges
  case onlineWriteInProgress
  case photoActionNeedsReview

  var errorDescription: String? {
    switch self {
    case .pendingChanges: "Synchronize or resolve this item's pending changes before continuing."
    case .photoActionNeedsReview: "Review the refreshed photos before changing this page again."
    case .onlineWriteInProgress: "Wait for the current save to finish, then try again."
    }
  }
}
