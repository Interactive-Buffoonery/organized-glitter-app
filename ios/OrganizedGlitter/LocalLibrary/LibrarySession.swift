import Foundation
import Observation
import Network

@MainActor
@Observable
final class LibrarySession {
  let client: PocketBaseClient
  let scope: LocalAccountScope
  let store: LocalLibraryStore
  private let coordinator: LocalSyncCoordinator
  private var syncTask: Task<Void, Error>?
  private var active = true
  private var acceptsChanges = true
  private var onlineWrites = 0
  private var onlineRecords: Set<LocalRecordKey> = []

  private(set) var items: [LibraryItem] = []
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
  var conflicts: [LocalLibraryEntry] { entries.filter { $0.conflict != nil } }

  init(client: PocketBaseClient, userID: String, store: LocalLibraryStore) {
    self.client = client
    self.scope = LocalAccountScope(backendURL: client.baseURL, userID: userID)
    self.store = store
    self.coordinator = LocalSyncCoordinator(store: store, client: client, scope: scope)
  }

  func loadLocal() async throws {
    try checkActive()
    let loaded = try await store.entries(scope: scope)
    let notes = try await store.notes(scope: scope)
    let complete = try await store.hasSnapshot(scope: scope)
    let pending = try await store.pendingCount(scope: scope)
    try checkActive()
    entries = loaded
    items = loaded.map(\.item)
    progressNotes = notes.diamonds
    coloringPageProgressNotes = notes.coloring
    hasSnapshot = complete
    pendingCount = pending
  }

  func refresh(force: Bool = false) async throws {
    try checkActive()
    if onlineWrites > 0 { return }
    if let syncTask { return try await syncTask.value }
    let task = Task { [weak self] in
      guard let self else { return }
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
        self.syncMessage = nil
        self.generation &+= 1
      } catch {
        guard self.active else { throw APIError.cancelled }
        try await self.loadLocal()
        if error as? APIError == .unauthenticated || error as? APIError == .forbidden {
          self.syncMessage = "Sign in again to synchronize your saved changes."
          Task { await self.onAuthenticationFailure?() }
          throw error
        }
        if error as? APIError == .cancelled || error is CancellationError { throw error }
        self.syncMessage = self.hasSnapshot
          ? "Showing your downloaded library. Changes will sync when the service is available."
          : "Connect to download your library."
        if !self.hasSnapshot { throw error }
      }
    }
    syncTask = task
    defer { syncTask = nil }
    try await task.value
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
    let patch = try JSONDecoder().decode(
      [String: LocalJSONValue].self, from: JSONEncoder().encode(body))
    if patch.isEmpty { return try record(collection: collection, id: id) }
    let entry = try await store.queueEdit(
      scope: scope, key: LocalRecordKey(kind: kind, id: id), patch: patch)
    try checkActive()
    try await loadLocal()
    generation &+= 1
    Task { try? await refresh() }
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
    try await beginOnlineWrite()
    defer { endOnlineWrite() }
    let saved: Record = try await client.create(collection: collection, body: body)
    try checkActive()
    try await acceptOnline(saved)
    return saved
  }

  func create<Record: Decodable & Sendable>(
    collection: String, multipart: PocketBaseMultipartForm
  ) async throws -> Record {
    try await beginOnlineWrite()
    defer { endOnlineWrite() }
    let saved: Record = try await client.create(collection: collection, multipart: multipart)
    try checkActive()
    try await acceptOnline(saved)
    return saved
  }

  func updateOnline<Record: Decodable & Sendable>(
    collection: String, id: String, body: some Encodable & Sendable
  ) async throws -> Record {
    try await beginOnlineWrite()
    defer { endOnlineWrite() }
    let reserved = try await reserveOnlineRecord(collection: collection, id: id)
    defer { onlineRecords.subtract(reserved) }
    let saved: Record = try await client.update(collection: collection, id: id, body: body)
    try checkActive()
    try await acceptOnline(saved)
    return saved
  }

  func update<Record: Decodable & Sendable>(
    collection: String, id: String, multipart: PocketBaseMultipartForm
  ) async throws -> Record {
    try await beginOnlineWrite()
    defer { endOnlineWrite() }
    let reserved = try await reserveOnlineRecord(collection: collection, id: id)
    defer { onlineRecords.subtract(reserved) }
    let saved: Record = try await client.update(collection: collection, id: id, multipart: multipart)
    try checkActive()
    try await acceptOnline(saved)
    return saved
  }

  func delete(collection: String, id: String) async throws {
    try await beginOnlineWrite()
    defer { endOnlineWrite() }
    let reserved = try await reserveOnlineRecord(collection: collection, id: id)
    defer { onlineRecords.subtract(reserved) }
    try await client.delete(collection: collection, id: id)
    try checkActive()
    if let kind = LocalRecordKind(rawValue: collection) {
      do {
        try await store.removeConfirmed(scope: scope, key: LocalRecordKey(kind: kind, id: id))
        try await loadLocal()
        generation &+= 1
      } catch { syncMessage = "Removed from your account. Refresh to update this device." }
    }
    Task { try? await refresh(force: true) }
  }

  func resolve(_ entry: LocalLibraryEntry, retainLocal: Bool) async throws {
    try checkWritable()
    _ = try await store.resolveConflict(
      scope: scope, key: entry.item.localRecordKey, retainLocal: retainLocal)
    try await loadLocal()
    generation &+= 1
    Task { try? await refresh(force: true) }
  }

  func pauseWrites() { acceptsChanges = false }
  func resumeWrites() { if active { acceptsChanges = true } }

  func close(removingData: Bool) async throws {
    active = false
    syncTask?.cancel()
    await coordinator.cancel()
    if let task = syncTask { _ = await task.result }
    syncTask = nil
    items = []
    entries = []
    progressNotes = []
    coloringPageProgressNotes = []
    if removingData {
      try await store.removeScope(scope)
      try await client.removeDownloadedArtwork(scope: scope)
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
      throw error
    }
  }

  private func endOnlineWrite() {
    onlineWrites -= 1
    if onlineWrites == 0, active { Task { try? await refresh(force: true) } }
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

  var errorDescription: String? {
    "Synchronize or resolve this item's pending changes before continuing."
  }
}
