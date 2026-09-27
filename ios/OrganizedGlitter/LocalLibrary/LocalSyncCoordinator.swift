import Foundation

actor LocalSyncCoordinator {
  private let store: LocalLibraryStore
  private let client: PocketBaseClient
  let scope: LocalAccountScope
  private var generation = 0

  init(store: LocalLibraryStore, client: PocketBaseClient, scope: LocalAccountScope) {
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
    try await syncPending(expectedGeneration: generation)
  }

  private func syncPending(expectedGeneration: Int) async throws {
    // A promoted follow-up edit gets its own baseline and operation ID. The
    // bound also prevents a stream of new UI edits from keeping one call alive.
    for _ in 0..<1_000 {
      try checkActive(expectedGeneration)
      let operations = try await store.pendingOperations(scope: scope)
      guard let operation = operations.first else { return }
      do {
        let record = try await client.applyLocalOperation(operation)
        try checkActive(expectedGeneration)
        guard record.localRecordKey == operation.key else {
          throw LocalLibraryError.invalidValue
        }
        try await store.acknowledge(scope: scope, operationID: operation.id, record: record)
      } catch let conflict as LocalSyncConflict {
        try checkActive(expectedGeneration)
        guard conflict.current.localRecordKey == operation.key else {
          throw LocalLibraryError.invalidValue
        }
        try await store.recordConflict(
          scope: scope, operationID: operation.id, server: conflict.current)
      } catch APIError.validation {
        try checkActive(expectedGeneration)
        try await store.markRejected(
          scope: scope, operationID: operation.id, key: operation.key)
      }
    }
  }

  func refreshAndSync() async throws {
    let expectedGeneration = generation
    try await refresh(expectedGeneration: expectedGeneration)
    try checkActive(expectedGeneration)
    try await syncPending(expectedGeneration: expectedGeneration)
    try checkActive(expectedGeneration)
    try await refresh(expectedGeneration: expectedGeneration)
  }

  private func checkActive(_ expectedGeneration: Int) throws {
    try Task.checkCancellation()
    guard generation == expectedGeneration else { throw CancellationError() }
  }
}
