import Foundation
import Observation

@MainActor
@Observable
final class ColorKeysModel {
  enum LoadState: Equatable { case idle, loading, loaded, failed }

  let library: LibrarySession
  let pageID: String
  private(set) var keys: [ColorKeyRecord] = []
  private(set) var history: [ColorKeyRecord] = []
  private(set) var loadState = LoadState.idle
  private(set) var isSaving = false

  init(library: LibrarySession, pageID: String) {
    self.library = library
    self.pageID = pageID
  }

  var recentSymbols: [String] { ColorKeys.recentSymbols(history) }
  var nextPosition: Int { ColorKeys.nextPosition(after: keys) }

  func suggestions(for code: String) -> [ColorKeySuggestion] {
    ColorKeys.suggestions(for: code, history: history)
  }

  func copyText(catalog: SymbolCatalog = .bundled) -> String {
    ColorKeys.copyText(keys, catalog: catalog)
  }

  func newKey(symbol: String, position: Int? = nil) -> ColorKeyWrite {
    ColorKeyWrite(user: library.userID, page: pageID, position: position ?? nextPosition, symbol: symbol)
  }

  /// The key after `key` in position order, for "Save and next".
  func key(after key: ColorKeyRecord) -> ColorKeyRecord? {
    guard let index = keys.firstIndex(where: { $0.id == key.id }), keys.indices.contains(index + 1)
    else { return nil }
    return keys[index + 1]
  }

  func load() async {
    loadState = .loading
    do {
      async let keys = library.colorKeys(pageID: pageID)
      async let history = library.colorKeyHistory()
      self.keys = try await keys
      // Suggestions are optional; the page still works without them.
      self.history = (try? await history) ?? self.history
      loadState = .loaded
    } catch {
      loadState = Task.isCancelled ? .idle : .failed
    }
  }

  struct Failure: Error { let message: String }

  /// Saves `write` and returns the stored record, whose symbol may differ from the one sent.
  func save(_ write: ColorKeyWrite, id: String?) async -> Result<ColorKeyRecord, Failure> {
    let write = write.normalized
    if let message = ColorKeys.validationMessage(write) { return .failure(Failure(message: message)) }
    isSaving = true
    defer { isSaving = false }
    do {
      let saved = try await library.saveColorKey(write, id: id)
      accept(saved)
      return .success(saved)
    } catch {
      return .failure(Failure(message: message(for: error)))
    }
  }

  func delete(_ key: ColorKeyRecord) async -> String? {
    isSaving = true
    defer { isSaving = false }
    do {
      try await library.deleteColorKey(id: key.id)
      keys.removeAll { $0.id == key.id }
      history.removeAll { $0.id == key.id }
      return nil
    } catch {
      return message(for: error)
    }
  }

  /// Creates a key for each symbol in order. Symbols already on the page are
  /// skipped, so a retry after a failure only sends the rest.
  func setUp(symbols: [String]) async -> String? {
    let saved = Set(keys.map(\.symbol))
    isSaving = true
    defer { isSaving = false }
    for write in ColorKeys.setupWrites(symbols: symbols, user: library.userID, page: pageID)
    where !saved.contains(write.symbol) {
      do {
        accept(try await library.saveColorKey(write, id: nil))
      } catch {
        return message(for: error)
      }
    }
    return nil
  }

  private func accept(_ saved: ColorKeyRecord) {
    keys = ColorKeys.sorted(keys.filter { $0.id != saved.id } + [saved])
    history = [saved] + history.filter { $0.id != saved.id }
  }

  private func message(for error: Error) -> String {
    error.userMessage(
      permission: "You can only change colors on your own pages.",
      offline: APIError.needsConnection("Saving colors"),
      fallback: "Couldn’t save. Try again.")
  }
}
