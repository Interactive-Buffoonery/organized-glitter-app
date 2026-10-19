import Foundation

struct ColorKeyRecord: Decodable, Identifiable, Hashable, Sendable {
  let id: String
  let user: String
  let page: String
  let position: Int
  let symbol: String
  let code: String
  let colorName: String
  let swatch: String
  let tried: [String]
  let note: String
  let created: String
  let updated: String

  private enum CodingKeys: String, CodingKey {
    case id, user, page, position, symbol, code, swatch, tried, note, created, updated
    case colorName = "color_name"
  }

  init(id: String, user: String, page: String, position: Int, symbol: String, code: String,
    colorName: String, swatch: String, tried: [String], note: String, created: String, updated: String) {
    self.id = id
    self.user = user
    self.page = page
    self.position = position
    self.symbol = symbol
    self.code = code
    self.colorName = colorName
    self.swatch = swatch
    self.tried = tried
    self.note = note
    self.created = created
    self.updated = updated
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    user = try container.decode(String.self, forKey: .user)
    page = try container.decode(String.self, forKey: .page)
    symbol = try container.decode(String.self, forKey: .symbol)
    position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
    code = try container.decodeIfPresent(String.self, forKey: .code) ?? ""
    colorName = try container.decodeIfPresent(String.self, forKey: .colorName) ?? ""
    swatch = try container.decodeIfPresent(String.self, forKey: .swatch) ?? ""
    tried = try container.decodeIfPresent([String].self, forKey: .tried) ?? []
    note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    created = try container.decodeIfPresent(String.self, forKey: .created) ?? ""
    updated = try container.decodeIfPresent(String.self, forKey: .updated) ?? ""
  }

  var write: ColorKeyWrite {
    ColorKeyWrite(user: user, page: page, position: position, symbol: symbol, code: code,
      colorName: colorName, swatch: swatch, tried: tried, note: note)
  }
}

/// The full record sent on create. The server rejects a create without
/// `position`, so it is never optional here.
struct ColorKeyWrite: Encodable, Hashable, Sendable {
  var user: String
  var page: String
  var position: Int
  var symbol: String
  var code = ""
  var colorName = ""
  var swatch = ""
  var tried: [String] = []
  var note = ""

  fileprivate enum CodingKeys: String, CodingKey {
    case user, page, position, symbol, code, swatch, tried, note
    case colorName = "color_name"
  }

  var normalized: ColorKeyWrite {
    var write = self
    write.code = code.trimmingCharacters(in: .whitespacesAndNewlines)
    write.colorName = colorName.trimmingCharacters(in: .whitespacesAndNewlines)
    write.tried = tried.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    write.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    return write
  }
}

/// An update body with only the fields that differ from the loaded record.
/// `user` and `page` never change, so they are never sent.
struct ColorKeyPatch: Encodable, Sendable {
  let original: ColorKeyWrite
  let changed: ColorKeyWrite

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: ColorKeyWrite.CodingKeys.self)
    func encode<Value: Encodable & Equatable>(_ field: KeyPath<ColorKeyWrite, Value>,
      _ key: ColorKeyWrite.CodingKeys) throws {
      if original[keyPath: field] != changed[keyPath: field] {
        try container.encode(changed[keyPath: field], forKey: key)
      }
    }
    try encode(\.position, .position)
    try encode(\.symbol, .symbol)
    try encode(\.code, .code)
    try encode(\.colorName, .colorName)
    try encode(\.swatch, .swatch)
    try encode(\.tried, .tried)
    try encode(\.note, .note)
  }
}

struct ColorKeySuggestion: Hashable, Sendable {
  let code: String
  let colorName: String
  let swatch: String
}

enum ColorKeys {
  static let collection = "coloring_page_color_keys"
  static let maxTried = 20
  static let maxFieldLength = 100
  static let maxNoteLength = 2_000

  static func sorted(_ keys: [ColorKeyRecord]) -> [ColorKeyRecord] {
    keys.sorted { ($0.position, $0.created, $0.id) < ($1.position, $1.created, $1.id) }
  }

  /// One `<symbol> <code>` line per key. `u:` symbols copy their characters,
  /// custom shapes their catalog name, and requests "Sent symbol".
  static func copyText(_ keys: [ColorKeyRecord], catalog: SymbolCatalog,
    requests: [String: SymbolRequestRecord] = [:]) -> String {
    sorted(keys).map { key in
      let symbol = switch ColorKeySymbol(id: key.symbol) {
      case .unicode(let text): text
      case .request: requests[key.symbol]?.copyName ?? "Sent symbol"
      case .custom, nil: catalog.accessibilityName(for: key.symbol)
      }
      return key.code.isEmpty ? symbol : "\(symbol) \(key.code)"
    }.joined(separator: "\n")
  }

  /// Earlier codes that start with `prefix`, each with the name and swatch it was
  /// last saved with. `history` is most recently updated first.
  static func suggestions(for prefix: String, history: [ColorKeyRecord], limit: Int = 5)
    -> [ColorKeySuggestion]
  {
    let prefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prefix.isEmpty else { return [] }
    var seen: Set<String> = []
    var result: [ColorKeySuggestion] = []
    for key in history.sorted(by: { $0.updated > $1.updated }) where !key.code.isEmpty {
      let folded = key.code.lowercased()
      guard seen.insert(folded).inserted,
        key.code.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil
      else { continue }
      result.append(ColorKeySuggestion(code: key.code, colorName: key.colorName, swatch: key.swatch))
      if result.count == limit { break }
    }
    return result
  }

  /// The user's own symbols, most recently used first. Keys without a code are
  /// skipped so the blank keys from setup don't crowd out real use.
  static func recentSymbols(_ history: [ColorKeyRecord], limit: Int = 12) -> [String] {
    var seen: Set<String> = []
    return history.filter { !$0.code.isEmpty }.sorted { $0.updated > $1.updated }.map(\.symbol)
      .filter { ColorKeySymbol(id: $0) != nil && seen.insert($0).inserted }
      .prefix(limit).map { $0 }
  }

  static func setupWrites(symbols: [String], user: String, page: String) -> [ColorKeyWrite] {
    symbols.enumerated().map { ColorKeyWrite(user: user, page: page, position: $0, symbol: $1) }
  }

  static func nextPosition(after keys: [ColorKeyRecord]) -> Int {
    (keys.map(\.position).max() ?? -1) + 1
  }

  static func swatchHex(red: Double, green: Double, blue: Double) -> String {
    let channel = { (value: Double) in Int((min(max(value, 0), 1) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", channel(red), channel(green), channel(blue))
  }

  static func swatchComponents(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
    guard hex.wholeMatch(of: #/#[0-9A-Fa-f]{6}/#) != nil, let value = UInt32(hex.dropFirst(), radix: 16)
    else { return nil }
    return (Double(value >> 16 & 0xFF) / 255, Double(value >> 8 & 0xFF) / 255, Double(value & 0xFF) / 255)
  }

  static func validationMessage(_ write: ColorKeyWrite) -> String? {
    if ColorKeySymbol(id: write.symbol) == nil { return "Choose a symbol." }
    if write.code.count > maxFieldLength { return "Keep the code to 100 characters or fewer." }
    if write.colorName.count > maxFieldLength {
      return "Keep the color name to 100 characters or fewer."
    }
    if write.tried.count > maxTried { return "Add up to \(maxTried) colors tried." }
    if write.tried.contains(where: { $0.count > maxFieldLength }) {
      return "Keep each color tried to 100 characters or fewer."
    }
    if write.note.count > maxNoteLength { return "Keep the note to 2,000 characters or fewer." }
    return nil
  }
}

/// A photo of a symbol missing from the catalog. Its `r:<id>` works as a key's
/// symbol until the request is resolved.
struct SymbolRequestRecord: Decodable, Identifiable, Hashable, Sendable {
  let id: String
  let user: String
  let description: String
  let photo: String

  static let collection = "coloring_symbol_requests"

  var symbol: String { "r:\(id)" }

  /// The description on one line, or nil when there is none.
  var copyName: String? {
    let name = description.split(whereSeparator: \.isNewline).joined(separator: " ")
      .trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? nil : name
  }
}

/// What the user fills in to send a symbol request. The server sets `status`
/// and `resolved_symbol`, so they are never sent.
struct SymbolRequestDraft: Equatable, Sendable {
  var bookLabel: String
  var description = ""
  var email: String
  var photo: ProcessedDetailPhoto?

  var validationMessage: String? {
    let bookLabel = bookLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
    if photo == nil { return "Add a photo of the symbol." }
    if bookLabel.isEmpty { return "Add the book and page." }
    if bookLabel.count > 200 { return "Keep the book and page under 200 characters." }
    if description.count > 500 { return "Keep the description under 500 characters." }
    // ponytail: the server validates the address; this only catches obvious typos.
    if email.contains(where: \.isWhitespace) || !email.contains("@") { return "Enter your email address." }
    return nil
  }

  func form(user: String, page: String) -> PocketBaseMultipartForm {
    var fields = [
      "user": user, "page": page,
      "book_label": bookLabel.trimmingCharacters(in: .whitespacesAndNewlines),
      "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
    ]
    let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
    if !description.isEmpty { fields["description"] = description }
    return PocketBaseMultipartForm(fields: fields, files: photo.map {
      [PocketBaseMultipartFile(fieldName: "photo", fileName: $0.fileName, contentType: $0.contentType, data: $0.data)]
    } ?? [])
  }
}
