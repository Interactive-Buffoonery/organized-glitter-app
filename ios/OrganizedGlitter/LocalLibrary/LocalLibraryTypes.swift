import Foundation

struct LocalAccountScope: Hashable, Sendable {
  let backendURL: URL
  let userID: String

  init(backendURL: URL, userID: String) {
    self.backendURL = backendURL
    self.userID = userID
  }

  var storageKey: String {
    let origin = backendURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return "\(origin)|\(userID)"
  }
}

enum LocalJSONValue: Codable, Equatable, Sendable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case null

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if value.decodeNil() { self = .null }
    else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
    else if let number = try? value.decode(Double.self) { self = .number(number) }
    else { self = .string(try value.decode(String.self)) }
  }

  func encode(to encoder: Encoder) throws {
    var value = encoder.singleValueContainer()
    switch self {
    case .string(let string): try value.encode(string)
    case .number(let number): try value.encode(number)
    case .bool(let bool): try value.encode(bool)
    case .null: try value.encodeNil()
    }
  }
}

enum LocalRecordKind: String, Codable, Sendable {
  case project = "projects"
  case book = "coloring_books"
  case page = "coloring_pages"
}

struct LocalRecordKey: Hashable, Codable, Sendable {
  let kind: LocalRecordKind
  let id: String
}

enum LocalConflict: String, Codable, Sendable {
  case changedOnServer
  case deletedOnServer
  case rejectedByServer
}

struct LocalLibraryEntry: Sendable {
  let item: LibraryItem
  let pending: Bool
  let conflict: LocalConflict?
}

struct LocalLibraryProjection: Sendable {
  let entries: [LocalLibraryEntry]
  let progressNotes: [DiamondProgressNoteRecord]
  let coloringPageProgressNotes: [ColoringProgressNoteRecord]
  let hasSnapshot: Bool
  let pendingCount: Int
}

struct LocalPendingOperation: Codable, Sendable {
  let id: UUID
  let key: LocalRecordKey
  let base: [String: LocalJSONValue]
  let patch: [String: LocalJSONValue]
}

struct LocalConflictChange: Sendable {
  let field: String
  let local: LocalJSONValue
  let server: LocalJSONValue
  let isComparisonOnly: Bool
}

enum LocalLibraryError: Error, Equatable {
  case missingRecord
  case wrongAccount
  case unsupportedField
  case invalidValue
  case conflict
  case storageUnavailable
}

struct LocalSyncConflict: Error, Sendable {
  let current: LibraryItem
}

extension LibraryItem {
  var localRecordKey: LocalRecordKey {
    switch self {
    case .diamond(let record): LocalRecordKey(kind: .project, id: record.id)
    case .book(let record): LocalRecordKey(kind: .book, id: record.id)
    case .page(let record): LocalRecordKey(kind: .page, id: record.id)
    }
  }
}
