import Foundation

actor LocalSyncCoordinator {
  private let analytics: NativeAnalytics?
  private let store: LocalLibraryStore
  private let client: PocketBaseClient
  let scope: LocalAccountScope
  private var generation = 0

  init(store: LocalLibraryStore, client: PocketBaseClient, scope: LocalAccountScope, analytics: NativeAnalytics? = nil) {
    self.analytics = analytics
    self.store = store
    self.client = client
    self.scope = scope
  }

  func refresh() async throws {
    try await refresh(expectedGeneration: generation)
  }

  func cancel() {
    generation &+= 1
  }

  private func refresh(expectedGeneration: Int) async throws {
    let snapshot = try await client.mobileSnapshot()
    try checkActive(expectedGeneration)
    try await store.ingestSnapshot(snapshot, scope: scope)
  }

  func syncPending() async throws {
    _ = try await syncPending(expectedGeneration: generation)
  }

  private func syncPending(expectedGeneration: Int) async throws -> Bool {
    // A promoted follow-up edit gets its own baseline and operation ID. The
    // bound also prevents a stream of new UI edits from keeping one call alive.
    var attempted = false
    for _ in 0..<1_000 {
      try checkActive(expectedGeneration)
      guard let operation = try await store.nextPendingOperation(scope: scope) else {
        return attempted
      }
      attempted = true
      do {
        let record = try await client.applyLocalOperation(operation)
        try checkActive(expectedGeneration)
        guard record.localRecordKey == operation.key else {
          throw LocalLibraryError.invalidValue
        }
        try await store.acknowledge(scope: scope, operationID: operation.id, record: record)
        await analytics?.synchronized(operation, accountID: scope.userID)
      } catch let conflict as LocalSyncConflict {
        try checkActive(expectedGeneration)
        guard conflict.current.localRecordKey == operation.key else {
          throw LocalLibraryError.invalidValue
        }
        try await store.recordConflict(
          scope: scope, operationID: operation.id, server: conflict.current)
        await analytics?.capture(.syncConflict, properties: [
          "record_type": operation.key.kind.rawValue, "field_count": operation.patch.count,
        ], accountID: scope.userID)
      } catch APIError.validation {
        try checkActive(expectedGeneration)
        try await store.markRejected(
          scope: scope, operationID: operation.id, key: operation.key)
        await analytics?.capture(.syncRejected, properties: [
          "record_type": operation.key.kind.rawValue, "field_count": operation.patch.count,
        ], accountID: scope.userID)
      }
    }
    return attempted
  }

  func refreshAndSync() async throws {
    let expectedGeneration = generation
    try await refresh(expectedGeneration: expectedGeneration)
    try checkActive(expectedGeneration)
    let attempted = try await syncPending(expectedGeneration: expectedGeneration)
    try checkActive(expectedGeneration)
    if attempted { try await refresh(expectedGeneration: expectedGeneration) }
  }

  private func checkActive(_ expectedGeneration: Int) throws {
    try Task.checkCancellation()
    guard generation == expectedGeneration else { throw CancellationError() }
  }
}
