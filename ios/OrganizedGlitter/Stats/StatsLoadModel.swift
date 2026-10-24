import Foundation
import Observation

@MainActor
@Observable
final class StatsLoadModel {
  private(set) var snapshot: StatsSnapshot?
  private(set) var isLoading = false
  private(set) var isStale = false
  private(set) var errorMessage: String?
  private(set) var needsConnection = false
  private var libraryIdentity: ObjectIdentifier?
  private var loadedYear: Int?
  private var requestGeneration = 0

  func load(
    library: LibrarySession,
    year: Int,
    fetch: @MainActor (LibrarySession, Int) async throws -> StatsSnapshot = {
      try await $0.statsSnapshot(year: $1)
    }
  ) async {
    requestGeneration &+= 1
    let generation = requestGeneration
    let identity = ObjectIdentifier(library)
    if libraryIdentity != identity || loadedYear != year {
      snapshot = nil
      isStale = false
    }
    libraryIdentity = identity
    loadedYear = year
    isLoading = true
    errorMessage = nil
    needsConnection = false
    defer { if generation == requestGeneration { isLoading = false } }

    do {
      let result = try await fetch(library, year)
      guard generation == requestGeneration, !Task.isCancelled else { return }
      snapshot = result
      isStale = false
    } catch {
      guard generation == requestGeneration, !Task.isCancelled else { return }
      if error is CancellationError || error as? APIError == .cancelled { return }
      isStale = snapshot != nil
      needsConnection = error as? APIError == .offline
      errorMessage = error.userMessage(
        permission: "Stats are unavailable for this account.",
        offline: "Stats need a connection. Reconnect and try again.",
        fallback: "Stats couldn’t load. Try again.")
    }
  }

  func snapshot(for library: LibrarySession, year: Int) -> StatsSnapshot? {
    guard libraryIdentity == ObjectIdentifier(library), loadedYear == year else { return nil }
    return snapshot
  }

  func clear() {
    requestGeneration &+= 1
    libraryIdentity = nil
    loadedYear = nil
    snapshot = nil
    isStale = false
    isLoading = false
    errorMessage = nil
    needsConnection = false
  }
}
