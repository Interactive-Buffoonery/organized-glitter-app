import Foundation
import Observation

@MainActor
@Observable
final class ColorKeysModel {
  /// `unavailable` means the server has no color keys yet, so the page hides them.
  enum LoadState: Equatable { case idle, loading, loaded, failed, unavailable }

  let library: LibrarySession
  let pageID: String
  private(set) var keys: [ColorKeyRecord] = []
  private(set) var history: [ColorKeyRecord] = []
  private(set) var loadState = LoadState.idle
  private(set) var isSaving = false
  private var loadGeneration = 0
  private var revision = 0
  private var historyRequested = false
  /// A create that failed without a clear answer may still have been stored.
  /// No new create is sent until a reload shows the page, so a retry can't
  /// add the key twice.
  private var unconfirmedCreate: (write: ColorKeyWrite, knownIDs: Set<String>)?

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

  /// Loads the page's keys. A load that finishes after a newer one started, or
  /// after a local save, doesn't replace the rows.
  func load() async {
    loadGeneration &+= 1
    let generation = loadGeneration
    let startRevision = revision
    loadState = .loading
    do {
      let fetched = try await library.colorKeys(pageID: pageID)
      guard generation == loadGeneration else { return }
      if startRevision == revision { keys = fetched }
      loadState = .loaded
    } catch {
      guard generation == loadGeneration else { return }
      if Task.isCancelled {
        loadState = .idle
      } else {
        loadState = error as? APIError == .notFound ? .unavailable : .failed
      }
    }
  }

  /// Suggestions and recently used symbols are optional, so they load only when
  /// a sheet needs them, and a failure leaves the sheet usable.
  func loadHistoryIfNeeded() async {
    guard !historyRequested else { return }
    historyRequested = true
    let startRevision = revision
    do {
      let fetched = try await library.colorKeyHistory()
      // A save or delete since the request started makes this copy stale; fetch again later.
      guard startRevision == revision else { return historyRequested = false }
      let fetchedIDs = Set(fetched.map(\.id))
      history = history.filter { !fetchedIDs.contains($0.id) } + fetched
    } catch {
      historyRequested = false
    }
  }

  struct Failure: Error { let message: String }

  /// Saves `write` and returns the stored record, whose symbol may differ from the one sent.
  /// An update sends only the fields that changed from the loaded key `id`.
  func save(_ write: ColorKeyWrite, id: String?) async -> Result<ColorKeyRecord, Failure> {
    let write = write.normalized
    if let message = ColorKeys.validationMessage(write) { return .failure(Failure(message: message)) }
    let original = id.flatMap { id in keys.first { $0.id == id } }
    guard !isSaving, id == nil || original != nil else {
      return .failure(Failure(message: Self.fallbackMessage))
    }
    isSaving = true
    defer { isSaving = false }
    if original == nil {
      let pending = unconfirmedCreate
      guard await confirmCreates() else { return .failure(Failure(message: unconfirmedMessage)) }
      if let pending, let landed = landedKey(pending, for: write) {
        return await saveRecovered(write, over: landed)
      }
    }
    let knownIDs = Set(keys.map(\.id))
    do {
      let saved = try await library.saveColorKey(write, original: original)
      accept(saved)
      return .success(saved)
    } catch {
      if original == nil, Self.isUncertain(error) {
        let pending = (write: write, knownIDs: knownIDs)
        unconfirmedCreate = pending
        if await confirmCreates(), let landed = landedKey(pending, for: write) {
          return await saveRecovered(write, over: landed)
        }
      }
      return .failure(Failure(message: message(for: error)))
    }
  }

  /// The create landed after all; any edits made since are sent as an update.
  private func saveRecovered(_ write: ColorKeyWrite, over landed: ColorKeyRecord)
    async -> Result<ColorKeyRecord, Failure> {
    var write = write
    if write.symbol.hasPrefix("r:") { write.symbol = landed.symbol }
    guard write != landed.write else {
      accept(landed)
      return .success(landed)
    }
    do {
      let saved = try await library.saveColorKey(write, original: landed)
      accept(saved)
      return .success(saved)
    } catch {
      return .failure(Failure(message: message(for: error)))
    }
  }

  func delete(id: String) async -> String? {
    guard !isSaving else { return Self.fallbackMessage }
    isSaving = true
    defer { isSaving = false }
    do {
      try await library.deleteColorKey(id: id)
      revision &+= 1
      keys.removeAll { $0.id == id }
      history.removeAll { $0.id == id }
      return nil
    } catch {
      return message(for: error, offline: APIError.deleteNeedsConnectionMessage)
    }
  }

  /// Creates a key for each symbol in order. Symbols already on the page are
  /// skipped, so a retry with the same symbols only sends the rest.
  func setUp(symbols: [String]) async -> String? {
    guard !isSaving else { return Self.fallbackMessage }
    isSaving = true
    defer { isSaving = false }
    guard await confirmCreates() else { return unconfirmedMessage }
    let saved = Set(keys.map(\.symbol))
    for write in ColorKeys.setupWrites(symbols: symbols, user: library.userID, page: pageID)
    where !saved.contains(write.symbol) {
      let knownIDs = Set(keys.map(\.id))
      do {
        accept(try await library.saveColorKey(write, original: nil))
      } catch {
        if Self.isUncertain(error) {
          unconfirmedCreate = (write, knownIDs)
          _ = await confirmCreates()
        }
        return message(for: error)
      }
    }
    return nil
  }

  private func accept(_ saved: ColorKeyRecord) {
    revision &+= 1
    keys = ColorKeys.sorted(keys.filter { $0.id != saved.id } + [saved])
    history = (saved.code.isEmpty ? [] : [saved]) + history.filter { $0.id != saved.id }
  }

  private static func isUncertain(_ error: Error) -> Bool {
    [.offline, .server, .decoding].contains(error as? APIError)
  }

  /// Reloads after an unconfirmed create. Returns false while the page can't
  /// be read, so the caller sends nothing.
  private func confirmCreates() async -> Bool {
    guard unconfirmedCreate != nil else { return true }
    guard library.connectionAvailable != false, !Task.isCancelled else { return false }
    await load()
    guard loadState == .loaded else { return false }
    unconfirmedCreate = nil
    return true
  }

  /// The key an unconfirmed create stored, if the reload shows one. The server
  /// may have swapped a request placeholder for its resolved symbol.
  private func landedKey(_ pending: (write: ColorKeyWrite, knownIDs: Set<String>),
    for write: ColorKeyWrite) -> ColorKeyRecord? {
    guard pending.write.position == write.position, pending.write.symbol == write.symbol else { return nil }
    return keys.last {
      !pending.knownIDs.contains($0.id) && $0.position == write.position
        && ($0.symbol == write.symbol || write.symbol.hasPrefix("r:"))
    }
  }

  private var unconfirmedMessage: String {
    library.connectionAvailable == false
      ? APIError.needsConnection("Saving colors")
      : "Couldn’t check whether your last color saved. Try again."
  }

  private static let fallbackMessage = "Couldn’t save. Try again."

  private func message(for error: Error,
    offline: String = APIError.needsConnection("Saving colors")) -> String {
    error.userMessage(
      permission: "You can only change colors on your own pages.",
      offline: offline,
      fallback: Self.fallbackMessage)
  }
}
