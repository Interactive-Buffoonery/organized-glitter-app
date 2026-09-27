import Foundation
import SwiftData

@Model
final class LocalStoredRecord {
  @Attribute(.unique) var key: String
  var scope: String
  var kind: String
  var recordID: String
  var serverData: Data
  var activeData: Data?
  var nextData: Data?
  var nextBaseData: Data?
  var conflictValue: String?

  init(key: String, scope: String, kind: String, recordID: String, serverData: Data) {
    self.key = key
    self.scope = scope
    self.kind = kind
    self.recordID = recordID
    self.serverData = serverData
  }
}

@Model
final class LocalStoredAccount {
  @Attribute(.unique) var scope: String
  var userData: Data
  var hasSnapshot: Bool

  init(scope: String, userData: Data, hasSnapshot: Bool = false) {
    self.scope = scope
    self.userData = userData
    self.hasSnapshot = hasSnapshot
  }
}

@Model
final class LocalStoredNote {
  @Attribute(.unique) var key: String
  var scope: String
  var kind: String
  var recordData: Data

  init(key: String, scope: String, kind: String, recordData: Data) {
    self.key = key
    self.scope = scope
    self.kind = kind
    self.recordData = recordData
  }
}

struct LocalFullSnapshot: Decodable, Sendable {
  let version: Int
  let projects: [DiamondProjectRecord]
  let coloringBooks: [ColoringBookRecord]
  let coloringPages: [ColoringPageRecord]
  let progressNotes: [DiamondProgressNoteRecord]
  let coloringPageProgressNotes: [ColoringProgressNoteRecord]
}

actor LocalLibraryStore {
  private let context: ModelContext
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(databaseURL: URL) throws {
    let directory = databaseURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try directory.setResourceValues(excludedFromBackup: true)
    try FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: directory.path)
    let schema = Schema([LocalStoredRecord.self, LocalStoredAccount.self, LocalStoredNote.self])
    let configuration = ModelConfiguration(
      "LocalLibrary", schema: schema, url: databaseURL, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    context = ModelContext(container)
    context.autosaveEnabled = false
  }

  static func inMemory() throws -> LocalLibraryStore {
    let schema = Schema([LocalStoredRecord.self, LocalStoredAccount.self, LocalStoredNote.self])
    let configuration = ModelConfiguration(
      "LocalLibraryTests", schema: schema, isStoredInMemoryOnly: true,
      cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    return LocalLibraryStore(container: container)
  }

  private init(container: ModelContainer) {
    context = ModelContext(container)
    context.autosaveEnabled = false
  }

  func saveUser(_ user: UserRecord, scope: LocalAccountScope) throws {
    guard user.id == scope.userID else { throw LocalLibraryError.wrongAccount }
    let data = try encoder.encode(user)
    let scopeKey = scope.storageKey
    if let stored = try account(scopeKey) {
      stored.userData = data
    } else {
      context.insert(LocalStoredAccount(scope: scopeKey, userData: data))
    }
    try commit()
  }

  func loadUser(scope: LocalAccountScope) throws -> UserRecord? {
    guard let stored = try account(scope.storageKey) else { return nil }
    guard !stored.userData.isEmpty else { return nil }
    let user = try decoder.decode(UserRecord.self, from: stored.userData)
    guard user.id == scope.userID else { throw LocalLibraryError.wrongAccount }
    return user
  }

  func hasSnapshot(scope: LocalAccountScope) throws -> Bool {
    try account(scope.storageKey)?.hasSnapshot == true
  }

  func ingestSnapshot(_ snapshot: LocalFullSnapshot, scope: LocalAccountScope) throws {
    guard snapshot.version == 1 else { throw LocalLibraryError.invalidValue }
    var incoming: [(LocalRecordKey, Data)] = []
    for record in snapshot.projects {
      guard record.user == scope.userID else { throw LocalLibraryError.wrongAccount }
      incoming.append((LocalRecordKey(kind: .project, id: record.id), try encoder.encode(record)))
    }
    for record in snapshot.coloringBooks {
      guard record.user == scope.userID else { throw LocalLibraryError.wrongAccount }
      incoming.append((LocalRecordKey(kind: .book, id: record.id), try encoder.encode(record)))
    }
    let bookIDs = Set(snapshot.coloringBooks.map(\.id))
    for record in snapshot.coloringPages {
      guard bookIDs.contains(record.book) else { throw LocalLibraryError.wrongAccount }
      incoming.append((LocalRecordKey(kind: .page, id: record.id), try encoder.encode(record)))
    }
    let projectIDs = Set(snapshot.projects.map(\.id))
    let pageIDs = Set(snapshot.coloringPages.map(\.id))
    var notes: [(String, String, Data)] = []
    for note in snapshot.progressNotes {
      guard projectIDs.contains(note.project) else { throw LocalLibraryError.wrongAccount }
      notes.append(("diamond:\(note.id)", "diamond", try encoder.encode(note)))
    }
    for note in snapshot.coloringPageProgressNotes {
      guard note.user == scope.userID, pageIDs.contains(note.page) else {
        throw LocalLibraryError.wrongAccount
      }
      notes.append(("coloring:\(note.id)", "coloring", try encoder.encode(note)))
    }

    let scopeKey = scope.storageKey
    let existing = try storedRecords(scopeKey)
    let byKey = Dictionary(uniqueKeysWithValues: existing.map { ($0.key, $0) })
    let incomingKeys = Set(incoming.map { storageKey(scope: scopeKey, key: $0.0) })
    let existingNotes = try storedNotes(scopeKey)
    let notesByKey = Dictionary(uniqueKeysWithValues: existingNotes.map { ($0.key, $0) })
    let noteKeys = Set(notes.map { "\(scopeKey)|\($0.0)" })
    do {
      try context.transaction {
        if let account = try account(scopeKey) {
          account.hasSnapshot = true
        } else {
          context.insert(LocalStoredAccount(
            scope: scopeKey, userData: Data(), hasSnapshot: true))
        }
        for (recordKey, data) in incoming {
          let key = storageKey(scope: scopeKey, key: recordKey)
          if let stored = byKey[key] {
            stored.serverData = data
            if stored.activeData == nil { stored.conflictValue = nil }
          } else {
            context.insert(LocalStoredRecord(
              key: key, scope: scopeKey, kind: recordKey.kind.rawValue,
              recordID: recordKey.id, serverData: data))
          }
        }
        for stored in existing where !incomingKeys.contains(stored.key) {
          if stored.activeData != nil {
            stored.conflictValue = LocalConflict.deletedOnServer.rawValue
          } else {
            context.delete(stored)
          }
        }
        for (noteKey, kind, data) in notes {
          let key = "\(scopeKey)|\(noteKey)"
          if let stored = notesByKey[key] { stored.recordData = data }
          else {
            context.insert(LocalStoredNote(
              key: key, scope: scopeKey, kind: kind, recordData: data))
          }
        }
        for stored in existingNotes where !noteKeys.contains(stored.key) {
          context.delete(stored)
        }
        try context.save()
      }
    } catch {
      context.rollback()
      throw error
    }
  }

  func ingest(_ item: LibraryItem, scope: LocalAccountScope) throws {
    try verify(item, scope: scope)
    let key = item.localRecordKey
    let scopeKey = scope.storageKey
    let data = try data(for: item)
    if let stored = try record(scopeKey, key) {
      stored.serverData = data
    } else {
      context.insert(LocalStoredRecord(
        key: storageKey(scope: scopeKey, key: key), scope: scopeKey,
        kind: key.kind.rawValue, recordID: key.id, serverData: data))
    }
    try commit()
  }

  func entries(scope: LocalAccountScope, kind: LocalRecordKind? = nil) throws
    -> [LocalLibraryEntry]
  {
    try storedRecords(scope.storageKey).compactMap { stored in
      if let kind, stored.kind != kind.rawValue { return nil }
      return try entry(stored)
    }
  }

  func entry(scope: LocalAccountScope, key: LocalRecordKey) throws -> LocalLibraryEntry? {
    guard let stored = try record(scope.storageKey, key) else { return nil }
    return try entry(stored)
  }

  func notes(scope: LocalAccountScope) throws
    -> (diamonds: [DiamondProgressNoteRecord], coloring: [ColoringProgressNoteRecord])
  {
    var diamonds: [DiamondProgressNoteRecord] = []
    var coloring: [ColoringProgressNoteRecord] = []
    for note in try storedNotes(scope.storageKey) {
      if note.kind == "diamond" {
        diamonds.append(try decoder.decode(DiamondProgressNoteRecord.self, from: note.recordData))
      } else {
        coloring.append(try decoder.decode(ColoringProgressNoteRecord.self, from: note.recordData))
      }
    }
    return (diamonds, coloring)
  }

  func ingestNote(_ note: DiamondProgressNoteRecord, scope: LocalAccountScope) throws {
    guard try record(scope.storageKey, LocalRecordKey(kind: .project, id: note.project)) != nil
    else { throw LocalLibraryError.wrongAccount }
    try upsertNote(
      key: "diamond:\(note.id)", kind: "diamond", data: encoder.encode(note), scope: scope)
  }

  func ingestNote(_ note: ColoringProgressNoteRecord, scope: LocalAccountScope) throws {
    guard note.user == scope.userID,
      try record(scope.storageKey, LocalRecordKey(kind: .page, id: note.page)) != nil
    else { throw LocalLibraryError.wrongAccount }
    try upsertNote(
      key: "coloring:\(note.id)", kind: "coloring", data: encoder.encode(note), scope: scope)
  }

  private func upsertNote(
    key: String, kind: String, data: Data, scope: LocalAccountScope
  ) throws {
    let scopeKey = scope.storageKey
    let storageKey = "\(scopeKey)|\(key)"
    var descriptor = FetchDescriptor<LocalStoredNote>(
      predicate: #Predicate { $0.key == storageKey })
    descriptor.fetchLimit = 1
    if let stored = try context.fetch(descriptor).first {
      stored.recordData = data
    } else {
      context.insert(LocalStoredNote(
        key: storageKey, scope: scopeKey, kind: kind, recordData: data))
    }
    try commit()
  }

  @discardableResult
  func queueEdit(
    scope: LocalAccountScope, key: LocalRecordKey,
    patch: [String: LocalJSONValue]
  ) throws -> LocalLibraryEntry {
    guard !patch.isEmpty else { throw LocalLibraryError.invalidValue }
    guard patch.keys.allSatisfy({ Self.allowedFields[key.kind]?.contains($0) == true }) else {
      throw LocalLibraryError.unsupportedField
    }
    guard let stored = try record(scope.storageKey, key) else {
      throw LocalLibraryError.missingRecord
    }
    guard stored.conflictValue == nil else { throw LocalLibraryError.conflict }
    var visible = try jsonObject(stored.serverData)
    if let activeData = stored.activeData {
      let active = try decoder.decode(LocalPendingOperation.self, from: activeData)
      visible = try overlay(visible, with: active.patch)
    }
    if let nextData = stored.nextData {
      visible = try overlay(visible, with: decoder.decode([String: LocalJSONValue].self, from: nextData))
    }
    _ = try overlay(visible, with: patch).validated(as: key.kind, decoder: decoder)

    if stored.activeData == nil {
      let server = try jsonObject(stored.serverData)
      let base = try values(for: baselineFields(for: key.kind, patch: patch), in: server)
      let operation = LocalPendingOperation(id: UUID(), key: key, base: base, patch: patch)
      stored.activeData = try encoder.encode(operation)
    } else {
      var next = try stored.nextData.map {
        try decoder.decode([String: LocalJSONValue].self, from: $0)
      } ?? [:]
      var nextBase = try stored.nextBaseData.map {
        try decoder.decode([String: LocalJSONValue].self, from: $0)
      } ?? [:]
      let fields = baselineFields(for: key.kind, patch: patch)
      let newlyObserved = try values(for: fields, in: visible)
      for field in fields where nextBase[field] == nil {
        nextBase[field] = newlyObserved[field]
      }
      next.merge(patch) { _, newest in newest }
      stored.nextData = try encoder.encode(next)
      stored.nextBaseData = try encoder.encode(nextBase)
    }
    try commit()
    return try entry(stored)
  }

  func pendingOperations(scope: LocalAccountScope) throws -> [LocalPendingOperation] {
    try storedRecords(scope.storageKey).compactMap { stored in
      guard let data = stored.activeData, stored.conflictValue == nil else { return nil }
      return try decoder.decode(LocalPendingOperation.self, from: data)
    }
  }

  func pendingCount(scope: LocalAccountScope) throws -> Int {
    try storedRecords(scope.storageKey).filter { $0.activeData != nil }.count
  }

  func conflictChanges(scope: LocalAccountScope, key: LocalRecordKey) throws
    -> [LocalConflictChange]
  {
    guard let stored = try record(scope.storageKey, key),
      stored.conflictValue == LocalConflict.changedOnServer.rawValue,
      let activeData = stored.activeData
    else { return [] }
    let active = try decoder.decode(LocalPendingOperation.self, from: activeData)
    var desired = active.patch
    if let nextData = stored.nextData {
      desired.merge(try decoder.decode([String: LocalJSONValue].self, from: nextData)) {
        _, newest in newest
      }
    }
    let server = try jsonObject(stored.serverData)
    let current = try values(for: Array(desired.keys), in: server)
    return desired.keys.sorted().compactMap { field in
      guard let local = desired[field], let server = current[field], local != server else {
        return nil
      }
      return LocalConflictChange(field: field, local: local, server: server)
    }
  }

  @discardableResult
  func acknowledge(
    scope: LocalAccountScope, operationID: UUID, record item: LibraryItem
  ) throws -> LocalLibraryEntry? {
    try verify(item, scope: scope)
    guard let stored = try record(scope.storageKey, item.localRecordKey),
      let activeData = stored.activeData
    else { return nil }
    let active = try decoder.decode(LocalPendingOperation.self, from: activeData)
    guard active.id == operationID else { return try entry(stored) }
    let serverData = try data(for: item)
    let next = try stored.nextData.map {
      try decoder.decode([String: LocalJSONValue].self, from: $0)
    } ?? [:]
    let nextBase = try stored.nextBaseData.map {
      try decoder.decode([String: LocalJSONValue].self, from: $0)
    }
    let server = try jsonObject(serverData)
    let serverValues = try values(
      for: nextBase.map { Array($0.keys) } ?? Array(next.keys), in: server)
    let remaining = next.filter { serverValues[$0.key] != $0.value }
    let changedSinceQueued = nextBase.map { base in
      base.contains { serverValues[$0.key] != $0.value }
    } ?? !remaining.isEmpty
    stored.serverData = serverData
    stored.nextData = nil
    stored.nextBaseData = nil
    stored.conflictValue = remaining.isEmpty || !changedSinceQueued
      ? nil : LocalConflict.changedOnServer.rawValue
    if remaining.isEmpty {
      stored.activeData = nil
    } else {
      stored.activeData = try encoder.encode(LocalPendingOperation(
        id: UUID(), key: active.key,
        base: try nextBase ?? values(
          for: baselineFields(for: active.key.kind, patch: remaining), in: server),
        patch: remaining))
    }
    try commit()
    return try entry(stored)
  }

  @discardableResult
  func recordConflict(
    scope: LocalAccountScope, operationID: UUID, server item: LibraryItem
  ) throws -> LocalLibraryEntry? {
    try verify(item, scope: scope)
    guard let stored = try record(scope.storageKey, item.localRecordKey),
      let activeData = stored.activeData
    else { return nil }
    let active = try decoder.decode(LocalPendingOperation.self, from: activeData)
    guard active.id == operationID else { return try entry(stored) }
    stored.serverData = try data(for: item)
    stored.conflictValue = LocalConflict.changedOnServer.rawValue
    try commit()
    return try entry(stored)
  }

  func markRejected(scope: LocalAccountScope, operationID: UUID, key: LocalRecordKey) throws {
    guard let stored = try record(scope.storageKey, key),
      let activeData = stored.activeData,
      try decoder.decode(LocalPendingOperation.self, from: activeData).id == operationID
    else { return }
    stored.conflictValue = LocalConflict.rejectedByServer.rawValue
    try commit()
  }

  @discardableResult
  func resolveConflict(
    scope: LocalAccountScope, key: LocalRecordKey, retainLocal: Bool
  ) throws -> LocalLibraryEntry? {
    guard let stored = try record(scope.storageKey, key), stored.conflictValue != nil else {
      return nil
    }
    if stored.conflictValue == LocalConflict.deletedOnServer.rawValue {
      guard !retainLocal else { throw LocalLibraryError.missingRecord }
      context.delete(stored)
      try commit()
      return nil
    }
    if stored.conflictValue == LocalConflict.rejectedByServer.rawValue, retainLocal {
      throw LocalLibraryError.conflict
    }
    if retainLocal {
      let active = try stored.activeData.map {
        try decoder.decode(LocalPendingOperation.self, from: $0)
      }
      var desired = active?.patch ?? [:]
      if let nextData = stored.nextData {
        desired.merge(try decoder.decode([String: LocalJSONValue].self, from: nextData)) {
          _, newest in newest
        }
      }
      let server = try jsonObject(stored.serverData)
      let serverValues = try values(for: Array(desired.keys), in: server)
      desired = desired.filter { serverValues[$0.key] != $0.value }
      stored.activeData = desired.isEmpty ? nil : try encoder.encode(LocalPendingOperation(
        id: UUID(), key: key,
        base: try values(for: baselineFields(for: key.kind, patch: desired), in: server),
        patch: desired))
    } else {
      stored.activeData = nil
    }
    stored.nextData = nil
    stored.nextBaseData = nil
    stored.conflictValue = nil
    try commit()
    return try entry(stored)
  }

  func removeScope(_ scope: LocalAccountScope) throws {
    let key = scope.storageKey
    do {
      try context.transaction {
        for record in try storedRecords(key) { context.delete(record) }
        for note in try storedNotes(key) { context.delete(note) }
        if let account = try account(key) { context.delete(account) }
        try context.save()
      }
    } catch {
      context.rollback()
      throw error
    }
  }

  func removeConfirmed(scope: LocalAccountScope, key: LocalRecordKey) throws {
    let scopeKey = scope.storageKey
    let records = try storedRecords(scopeKey)
    let notes = try storedNotes(scopeKey)
    let matching = records.filter { $0.kind == key.kind.rawValue && $0.recordID == key.id }
    var children: [LocalStoredRecord] = []
    if key.kind == .book {
      children = try records.filter { $0.kind == LocalRecordKind.page.rawValue }.filter {
        try decoder.decode(ColoringPageRecord.self, from: $0.serverData).book == key.id
      }
    }
    guard (matching + children).allSatisfy({ $0.activeData == nil }) else {
      throw LocalLibraryError.conflict
    }
    let pageIDs = Set(children.map(\.recordID))
    let matchingNotes = try notes.filter { note in
      if note.kind == "diamond", key.kind == .project {
        return try decoder.decode(DiamondProgressNoteRecord.self, from: note.recordData)
          .project == key.id
      }
      if note.kind == "coloring", key.kind == .page {
        return try decoder.decode(ColoringProgressNoteRecord.self, from: note.recordData)
          .page == key.id
      }
      if note.kind == "coloring", key.kind == .book {
        return try pageIDs.contains(
          decoder.decode(ColoringProgressNoteRecord.self, from: note.recordData).page)
      }
      return false
    }
    do {
      try context.transaction {
        for record in matching + children { context.delete(record) }
        for note in matchingNotes { context.delete(note) }
        try context.save()
      }
    } catch {
      context.rollback()
      throw error
    }
  }

  private static let allowedFields: [LocalRecordKind: Set<String>] = [
    .project: [
      "title", "status", "kit_category", "drill_shape", "source_url", "general_notes",
      "date_purchased", "date_received", "date_started", "date_completed",
      "width", "height", "total_diamonds", "color_count", "company", "artist",
    ],
    .book: [
      "title", "series", "status", "date_started", "date_completed",
      "publisher", "illustrator",
    ],
    .page: ["status", "revealed_subject", "started_at", "completed_at"],
  ]

  private func baselineFields(
    for kind: LocalRecordKind, patch: [String: LocalJSONValue]
  ) -> [String] {
    let lifecycle: Set<String>
    switch kind {
    case .project, .book:
      lifecycle = ["status", "date_started", "date_completed"]
    case .page:
      lifecycle = ["status", "started_at", "completed_at", "revealed_at", "revealed_subject"]
    }
    var fields = Set(patch.keys)
    if !fields.isDisjoint(with: lifecycle) { fields.formUnion(lifecycle) }
    return Array(fields)
  }

  private func entry(_ stored: LocalStoredRecord) throws -> LocalLibraryEntry {
    var object = try jsonObject(stored.serverData)
    if let activeData = stored.activeData {
      object = try overlay(
        object, with: decoder.decode(LocalPendingOperation.self, from: activeData).patch)
    }
    if let nextData = stored.nextData {
      object = try overlay(
        object, with: decoder.decode([String: LocalJSONValue].self, from: nextData))
    }
    guard let kind = LocalRecordKind(rawValue: stored.kind) else {
      throw LocalLibraryError.invalidValue
    }
    let item = try object.validated(as: kind, decoder: decoder)
    return LocalLibraryEntry(
      item: item, pending: stored.activeData != nil,
      conflict: stored.conflictValue.flatMap(LocalConflict.init(rawValue:)))
  }

  private func verify(_ item: LibraryItem, scope: LocalAccountScope) throws {
    switch item {
    case .diamond(let record):
      guard record.user == scope.userID else { throw LocalLibraryError.wrongAccount }
    case .book(let record):
      guard record.user == scope.userID else { throw LocalLibraryError.wrongAccount }
    case .page(let page):
      let parentKey = LocalRecordKey(kind: .book, id: page.book)
      guard let parent = try record(scope.storageKey, parentKey),
        try decoder.decode(ColoringBookRecord.self, from: parent.serverData).user == scope.userID
      else { throw LocalLibraryError.wrongAccount }
    }
  }

  private func data(for item: LibraryItem) throws -> Data {
    switch item {
    case .diamond(let record): try encoder.encode(record)
    case .book(let record): try encoder.encode(record)
    case .page(let record): try encoder.encode(record)
    }
  }

  private func jsonObject(_ data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw LocalLibraryError.invalidValue
    }
    return object
  }

  private func overlay(
    _ object: [String: Any], with patch: [String: LocalJSONValue]
  ) throws -> [String: Any] {
    let data = try encoder.encode(patch)
    guard let values = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw LocalLibraryError.invalidValue
    }
    return object.merging(values) { _, new in new }
  }

  private func values(
    for fields: [String], in object: [String: Any]
  ) throws -> [String: LocalJSONValue] {
    var result: [String: LocalJSONValue] = [:]
    for field in fields {
      let data = try JSONSerialization.data(withJSONObject: [field: object[field] ?? NSNull()])
      result[field] = try decoder.decode([String: LocalJSONValue].self, from: data)[field]
    }
    return result
  }

  private func storageKey(scope: String, key: LocalRecordKey) -> String {
    "\(scope)|\(key.kind.rawValue)|\(key.id)"
  }

  private func record(_ scope: String, _ key: LocalRecordKey) throws -> LocalStoredRecord? {
    let storageKey = storageKey(scope: scope, key: key)
    var descriptor = FetchDescriptor<LocalStoredRecord>(
      predicate: #Predicate { $0.key == storageKey })
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }

  private func storedRecords(_ scope: String) throws -> [LocalStoredRecord] {
    try context.fetch(FetchDescriptor<LocalStoredRecord>(
      predicate: #Predicate { $0.scope == scope }))
  }

  private func storedNotes(_ scope: String) throws -> [LocalStoredNote] {
    try context.fetch(FetchDescriptor<LocalStoredNote>(
      predicate: #Predicate { $0.scope == scope }))
  }

  private func account(_ scope: String) throws -> LocalStoredAccount? {
    var descriptor = FetchDescriptor<LocalStoredAccount>(
      predicate: #Predicate { $0.scope == scope })
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }

  private func commit() throws {
    do { try context.save() }
    catch {
      context.rollback()
      throw error
    }
  }
}

private extension URL {
  func setResourceValues(excludedFromBackup: Bool) throws {
    var mutable = self
    var values = URLResourceValues()
    values.isExcludedFromBackup = excludedFromBackup
    try mutable.setResourceValues(values)
  }
}

private extension Dictionary where Key == String, Value == Any {
  func validated(as kind: LocalRecordKind, decoder: JSONDecoder) throws -> LibraryItem {
    let data = try JSONSerialization.data(withJSONObject: self)
    switch kind {
    case .project: return .diamond(try decoder.decode(DiamondProjectRecord.self, from: data))
    case .book: return .book(try decoder.decode(ColoringBookRecord.self, from: data))
    case .page: return .page(try decoder.decode(ColoringPageRecord.self, from: data))
    }
  }
}
