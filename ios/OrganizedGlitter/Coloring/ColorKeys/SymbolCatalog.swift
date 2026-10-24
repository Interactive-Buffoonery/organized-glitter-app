import CoreText
import Foundation
import SwiftUI
import UIKit

/// A parsed color key symbol ID, as defined in the shared color keys contract.
enum ColorKeySymbol: Hashable, Sendable {
  case unicode(String)
  case custom(String)
  case request(String)

  init?(id: String) {
    // One valid ID per symbol: shortest uppercase hex scalar values, at least 4 digits.
    // Each `u:` scalar is one of: a BMP value outside the surrogates (0000-D7FF,
    // E000-FFFF), a 5-digit plane 1-15 value, or 10xxxx for plane 16. Scalars
    // join with `-`. `c:` is a lowercase slug of 1-48 characters; `r:` is a
    // 15-character PocketBase record ID.
    let pattern = #/\A(u:(?:[0-9A-CE-F][0-9A-F]{3}|D[0-7][0-9A-F]{2}|[1-9A-F][0-9A-F]{4}|10[0-9A-F]{4})(-(?:[0-9A-CE-F][0-9A-F]{3}|D[0-7][0-9A-F]{2}|[1-9A-F][0-9A-F]{4}|10[0-9A-F]{4}))*|c:[a-z0-9-]{1,48}|r:[a-z0-9]{15})\z/#
    guard id.wholeMatch(of: pattern) != nil else { return nil }
    let value = String(id.dropFirst(2))
    switch id.prefix(2) {
    case "u:":
      var scalars = String.UnicodeScalarView()
      for hex in value.split(separator: "-") {
        guard let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) else {
          return nil
        }
        scalars.append(scalar)
      }
      self = .unicode(String(scalars))
    case "c:": self = .custom(value)
    default: self = .request(value)
    }
  }

  var id: String {
    switch self {
    case .unicode(let text): Self.unicodeID(for: text)
    case .custom(let slug): "c:\(slug)"
    case .request(let id): "r:\(id)"
    }
  }

  static let variationSelectors: Set<UInt32> = [0xFE0E, 0xFE0F]

  /// The text drawn for a `u:` symbol. Every renderer goes through here. Requests
  /// text presentation (U+FE0E) after each non-ASCII emoji-capable code point
  /// that has no variation selector yet. Display only; never stored or copied.
  static func displayText(_ text: String) -> String {
    var output = String.UnicodeScalarView()
    let scalars = Array(text.unicodeScalars)
    for (index, scalar) in scalars.enumerated() {
      output.append(scalar)
      let next = scalars.indices.contains(index + 1) ? scalars[index + 1].value : nil
      if scalar.value > 0x7F, scalar.properties.isEmoji,
        next.map(variationSelectors.contains) != true
      {
        output.append("\u{FE0E}")
      }
    }
    return String(output)
  }

  static func unicodeID(for text: String) -> String {
    "u:" + text.unicodeScalars.filter { !variationSelectors.contains($0.value) }
      .map { String(format: "%04X", $0.value) }.joined(separator: "-")
  }
}

/// The vendored copy of `src/features/coloring/colorKeys/symbolCatalog.json`
/// from organized-glitter-web.
struct SymbolCatalog: Decodable, Sendable {
  struct Group: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    let label: String
  }

  struct Symbol: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    let char: String?
    let name: String
    let group: String
    let keywords: [String]
    let path: String?
  }

  struct Section: Identifiable, Sendable {
    let group: Group
    let symbols: [Symbol]
    var id: String { group.id }
  }

  let version: Int
  let groups: [Group]
  let symbols: [Symbol]
  private let symbolsByID: [String: Symbol]
  /// Custom shapes, parsed once so views don't re-parse them on every render.
  private let pathsByID: [String: Path]

  private enum CodingKeys: String, CodingKey { case version, groups, symbols }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decode(Int.self, forKey: .version)
    groups = try container.decode([Group].self, forKey: .groups)
    symbols = try container.decode([Symbol].self, forKey: .symbols)
    var symbolsByID: [String: Symbol] = [:]
    for symbol in symbols where symbolsByID.updateValue(symbol, forKey: symbol.id) != nil {
      throw DecodingError.dataCorruptedError(
        forKey: .symbols, in: container, debugDescription: "Duplicate symbol ID \(symbol.id)")
    }
    self.symbolsByID = symbolsByID
    pathsByID = symbolsByID.compactMapValues { $0.path.flatMap(SymbolPath.parse) }
  }

  static let bundled: SymbolCatalog = {
    guard let url = Bundle.main.url(forResource: "symbolCatalog", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let catalog = try? JSONDecoder().decode(SymbolCatalog.self, from: data)
    else { preconditionFailure("The bundled symbol catalog is missing or invalid.") }
    return catalog
  }()

  /// Setup turns these on by default: 1-9, 0, then a-z.
  static let setupDefaults: [String] = Array("1234567890abcdefghijklmnopqrstuvwxyz").map {
    ColorKeySymbol.unicodeID(for: String($0))
  }

  func symbol(id: String) -> Symbol? { symbolsByID[id] }

  func path(id: String) -> Path? { pathsByID[id] }

  /// Matches ranked like the web app: the exact character, then name prefixes,
  /// keyword prefixes, then any substring. Ties keep catalog order.
  func search(_ query: String) -> [Symbol] {
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !term.isEmpty else { return symbols }
    func rank(_ symbol: Symbol) -> Int? {
      let name = symbol.name.lowercased()
      if symbol.char?.lowercased() == term { return 0 }
      if name.hasPrefix(term) { return 1 }
      if symbol.keywords.contains(where: { $0.hasPrefix(term) }) { return 2 }
      if name.contains(term) || symbol.keywords.contains(where: { $0.contains(term) }) { return 3 }
      return nil
    }
    return symbols.enumerated()
      .compactMap { index, symbol in rank(symbol).map { (rank: $0, index: index, symbol: symbol) } }
      .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
      .map(\.symbol)
  }

  func grouped(_ symbols: [Symbol]) -> [Section] {
    let byGroup = Dictionary(grouping: symbols, by: \.group)
    return groups.compactMap { group in
      byGroup[group.id].map { Section(group: group, symbols: $0) }
    }
  }

  func accessibilityName(for id: String) -> String {
    if let symbol = symbol(id: id) { return symbol.name }
    switch ColorKeySymbol(id: id) {
    case .unicode(let text): return text
    case .request: return "Requested symbol"
    case .custom, nil: return "Unknown symbol"
    }
  }
}

@MainActor
enum SymbolGlyphCoverage {
  // ponytail: cleared when full rather than LRU; the catalog plus a page's
  // keys fit well under the limit.
  private static let cacheLimit = 1_024
  private static var cache: [String: Bool] = [:]

  /// Whether a system font, including cascade fallbacks, has glyphs for `text`.
  /// Variation selectors have no glyphs of their own, so only base code points are checked.
  static func isRenderable(_ text: String) -> Bool {
    let text = String(String.UnicodeScalarView(text.unicodeScalars.filter {
      !ColorKeySymbol.variationSelectors.contains($0.value)
    }))
    if let cached = cache[text] { return cached }
    let base = UIFont.systemFont(ofSize: 17) as CTFont
    let length = (text as NSString).length
    let font = CTFontCreateForString(base, text as CFString, CFRange(location: 0, length: length))
    var characters = Array(text.utf16)
    var glyphs = [CGGlyph](repeating: 0, count: characters.count)
    let renderable = CTFontCopyPostScriptName(font) as String != "LastResort"
      && CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
    if cache.count >= cacheLimit { cache.removeAll() }
    cache[text] = renderable
    return renderable
  }

  /// The code points shown in place of text that no installed font can draw.
  static func fallbackLabel(for id: String) -> String {
    id.dropFirst(2).split(separator: "-").map { "U+\($0)" }.joined(separator: " ")
  }
}
