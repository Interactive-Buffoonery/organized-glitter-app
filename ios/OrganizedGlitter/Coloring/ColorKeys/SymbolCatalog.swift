import CoreText
import Foundation
import UIKit

/// A parsed color key symbol ID, as defined in the shared color keys contract.
enum ColorKeySymbol: Hashable, Sendable {
  case unicode(String)
  case custom(String)
  case request(String)

  init?(id: String) {
    // One valid ID per symbol: shortest uppercase hex scalar values, at least 4 digits.
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

  /// The text drawn for a `u:` symbol. Every renderer goes through here.
  // ponytail: identity until Sarah confirms the emoji presentation rule
  // (likely append U+FE0E here; never store it in IDs).
  static func displayText(_ text: String) -> String { text }

  static func unicodeID(for text: String) -> String {
    "u:" + text.unicodeScalars.map { String(format: "%04X", $0.value) }.joined(separator: "-")
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

  private enum CodingKeys: String, CodingKey { case version, groups, symbols }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decode(Int.self, forKey: .version)
    groups = try container.decode([Group].self, forKey: .groups)
    symbols = try container.decode([Symbol].self, forKey: .symbols)
    symbolsByID = Dictionary(symbols.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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

  func search(_ query: String) -> [Symbol] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return symbols }
    return symbols.filter { symbol in
      symbol.name.localizedCaseInsensitiveContains(query)
        || symbol.keywords.contains { $0.localizedCaseInsensitiveContains(query) }
    }
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
  private static var cache: [String: Bool] = [:]

  /// Whether a system font, including cascade fallbacks, has glyphs for `text`.
  static func isRenderable(_ text: String) -> Bool {
    let text = ColorKeySymbol.displayText(text)
    if let cached = cache[text] { return cached }
    let base = UIFont.systemFont(ofSize: 17) as CTFont
    let length = (text as NSString).length
    let font = CTFontCreateForString(base, text as CFString, CFRange(location: 0, length: length))
    var characters = Array(text.utf16)
    var glyphs = [CGGlyph](repeating: 0, count: characters.count)
    let renderable = CTFontCopyPostScriptName(font) as String != "LastResort"
      && CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
    cache[text] = renderable
    return renderable
  }

  /// The code points shown in place of text that no installed font can draw.
  static func fallbackLabel(for id: String) -> String {
    id.dropFirst(2).split(separator: "-").map { "U+\($0)" }.joined(separator: " ")
  }
}
