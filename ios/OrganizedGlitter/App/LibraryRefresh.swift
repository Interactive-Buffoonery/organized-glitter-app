import Observation

@MainActor
@Observable
final class LibraryRefresh {
  var generation = 0

  func bump() {
    generation += 1
  }
}
