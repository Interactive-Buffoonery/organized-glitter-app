import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import OrganizedGlitter

@Suite("Color key symbol IDs")
struct ColorKeySymbolIDTests {
  @Test("accepts contract IDs", arguments: [
    "u:0041", "u:03C8", "u:D7FF", "u:E000", "u:1F600", "u:0041-030A", "u:10FFFF",
    "c:linked-circles", "c:a", "r:abc123def456ghi",
  ])
  func acceptsValidIDs(id: String) {
    #expect(ColorKeySymbol(id: id)?.id == id)
  }

  @Test("rejects IDs outside the contract", arguments: [
    "", "u:3C8", "u:041", "u:00041", "u:003C8", "u:01F600", "u:03c8", "u:0041-", "u:0041-041",
    "u:1234567", "u:D800", "u:DFFF", "u:110000", "u:0041\n", "c:linked-circles\n", "r:abc123def456ghi\n", "c:", "c:Linked", "c:has space",
    "c:" + String(repeating: "a", count: 49), "r:short", "r:ABC123DEF456GHI", "x:03C8", " u:03C8",
  ])
  func rejectsInvalidIDs(id: String) {
    #expect(ColorKeySymbol(id: id) == nil)
  }

  @Test("decodes Unicode IDs into text, including IDs missing from the catalog")
  func decodesUnicode() {
    #expect(ColorKeySymbol(id: "u:03C8") == .unicode("ψ"))
    #expect(ColorKeySymbol(id: "u:0041-030A") == .unicode("A\u{030A}"))
    #expect(ColorKeySymbol(id: "u:2603") == .unicode("☃"))
  }

  @Test("builds Unicode IDs from text")
  func encodesUnicode() {
    #expect(ColorKeySymbol.unicodeID(for: "ψ") == "u:03C8")
    #expect(ColorKeySymbol.unicodeID(for: "😀") == "u:1F600")
    #expect(ColorKeySymbol.unicodeID(for: "A") == "u:0041")
  }

  @Test("built and decoded IDs round-trip to the single valid form")
  func roundTrips() {
    for id in ["u:0041", "u:03C8", "u:1F600", "u:10FFFF", "u:0041-030A"] {
      guard case .unicode(let text) = ColorKeySymbol(id: id) else {
        Issue.record("\(id) did not decode")
        continue
      }
      #expect(ColorKeySymbol.unicodeID(for: text) == id)
    }
  }
}

@Suite("Symbol catalog")
struct SymbolCatalogTests {
  let catalog = SymbolCatalog.bundled

  @Test("bundled catalog follows the shared contract")
  func followsContract() {
    #expect(catalog.version >= 1)
    #expect(catalog.groups.map(\.id) == [
      "numbers", "lowercase", "uppercase", "greek", "money", "math", "music", "signs",
      "letters-extra", "shapes",
    ])
    let groupIDs = Set(catalog.groups.map(\.id))
    #expect(Set(catalog.symbols.map(\.id)).count == catalog.symbols.count)
    for symbol in catalog.symbols {
      #expect(groupIDs.contains(symbol.group), "\(symbol.id) has unknown group")
      #expect(symbol.keywords.allSatisfy { $0 == $0.lowercased() }, "\(symbol.id) keywords")
      switch ColorKeySymbol(id: symbol.id) {
      case .unicode(let text):
        #expect(symbol.char == text, "\(symbol.id) char must equal its decoded ID")
        #expect(symbol.path == nil)
      case .custom:
        #expect(symbol.char == nil)
        #expect(symbol.path.flatMap(SymbolPath.parse) != nil, "\(symbol.id) path must parse")
      default:
        Issue.record("\(symbol.id) is not a catalog ID")
      }
    }
  }

  @Test("dropped emoji symbols stay out of the catalog")
  func droppedSymbols() {
    for id in ["u:2693", "u:2615", "u:26A1", "u:2795", "u:2796", "u:2797"] {
      #expect(catalog.symbol(id: id) == nil, "\(id) was dropped from the catalog")
    }
    #expect(catalog.symbols.allSatisfy { !($0.char ?? "").unicodeScalars.contains { [0xFE0E, 0xFE0F].contains($0.value) } })
    let emoji = catalog.symbols.filter { ($0.char ?? "").unicodeScalars.contains(where: \.properties.isEmojiPresentation) }
    #expect(emoji.map(\.id) == [])
  }

  @Test("setup defaults are 1-9, 0, then a-z")
  func setupDefaults() {
    let expected = Array("1234567890abcdefghijklmnopqrstuvwxyz").map {
      ColorKeySymbol.unicodeID(for: String($0))
    }
    #expect(SymbolCatalog.setupDefaults == expected)
    #expect(SymbolCatalog.setupDefaults.allSatisfy { catalog.symbol(id: $0) != nil })
  }

  @Test("search ranks the character, name prefixes, keyword prefixes, then substrings")
  func search() {
    for query in ["a", "pi", "circle", "triangle", "y"] {
      let ranks = catalog.search(query).map { symbol in
        if symbol.char?.lowercased() == query { return 0 }
        if symbol.name.lowercased().hasPrefix(query) { return 1 }
        if symbol.keywords.contains(where: { $0.hasPrefix(query) }) { return 2 }
        return 3
      }
      #expect(ranks.count > 1)
      #expect(ranks == ranks.sorted(), "\(query) results are out of rank order")
    }
    #expect(catalog.search("ψ").first?.id == "u:03C8")
    #expect(catalog.search(" PI ") == catalog.search("pi"))
    #expect(catalog.search("TRIDENT").map(\.id).contains("u:03C8"))
    #expect(catalog.search("psi").first?.id == "u:03C8")
    #expect(catalog.search("rings").map(\.id).contains("c:linked-circles"))
    #expect(catalog.search("  ").count == catalog.symbols.count)
    #expect(catalog.search("no such symbol").isEmpty)
  }

  @Test("groups symbols in group order")
  func grouped() {
    let sections = catalog.grouped(catalog.symbols)
    #expect(sections.map(\.group.id) == catalog.groups.map(\.id))
    #expect(sections.first?.symbols.first?.id == "u:0030")
  }

  @Test("accessibility names prefer the catalog")
  func accessibilityNames() {
    #expect(catalog.accessibilityName(for: "u:03C8") == "Psi")
    #expect(catalog.accessibilityName(for: "u:2603") == "Snowman")
    #expect(catalog.accessibilityName(for: "u:6F22") == "漢")
    #expect(catalog.accessibilityName(for: "c:linked-circles") == "Linked circles")
    #expect(catalog.accessibilityName(for: "c:not-in-catalog") == "Unknown symbol")
    #expect(catalog.accessibilityName(for: "r:abc123def456ghi") == "Requested symbol")
    #expect(catalog.accessibilityName(for: "garbage") == "Unknown symbol")
  }
}

@Suite("Symbol path parser")
struct SymbolPathTests {
  private func points(_ source: String) throws -> [CGPoint] {
    let path = try #require(SymbolPath.parse(source))
    var result: [CGPoint] = []
    path.cgPath.applyWithBlock { element in
      let element = element.pointee
      let count: Int
      switch element.type {
      case .moveToPoint, .addLineToPoint: count = 1
      case .addQuadCurveToPoint: count = 2
      case .addCurveToPoint: count = 3
      case .closeSubpath: count = 0
      @unknown default: count = 0
      }
      if count > 0 { result.append(element.points[count - 1]) }
    }
    return result
  }

  @Test("absolute and relative lines, including implicit line-tos after a move")
  func lines() throws {
    #expect(try points("M1 2L3 4H10V20") == [
      CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4), CGPoint(x: 10, y: 4), CGPoint(x: 10, y: 20),
    ])
    #expect(try points("m1 1 2 0l0 2h-2v-2") == [
      CGPoint(x: 1, y: 1), CGPoint(x: 3, y: 1), CGPoint(x: 3, y: 3), CGPoint(x: 1, y: 3),
      CGPoint(x: 1, y: 1),
    ])
  }

  @Test("compact numbers and comma separators")
  func compactNumbers() throws {
    #expect(try points("M.5.5L-1-1,2e1 1") == [
      CGPoint(x: 0.5, y: 0.5), CGPoint(x: -1, y: -1), CGPoint(x: 20, y: 1),
    ])
  }

  @Test("close path returns to the subpath start for later relative commands")
  func closeResetsCurrentPoint() throws {
    #expect(try points("M5 5l2 0zl1 1").last == CGPoint(x: 6, y: 6))
  }

  @Test("curves end at their final point")
  func curves() throws {
    #expect(try points("M0 0C1 1 2 2 3 3c1 0 1 0 1 1Q8 8 9 9q1 0 1 1").suffix(4) == [
      CGPoint(x: 3, y: 3), CGPoint(x: 4, y: 4), CGPoint(x: 9, y: 9), CGPoint(x: 10, y: 10),
    ])
  }

  @Test("arcs, including compact flags, reach their endpoint and stay in bounds")
  func arcs() throws {
    let path = try #require(SymbolPath.parse("M4 12a5 5 0 1 0 10 0a5 5 0 1 0 -10 0"))
    let bounds = path.boundingRect
    #expect(abs(bounds.minX - 4) < 0.01 && abs(bounds.maxX - 14) < 0.01)
    #expect(abs(bounds.minY - 7) < 0.01 && abs(bounds.maxY - 17) < 0.01)
    let compact = try points("M4 12a5 5 0 1010 0")
    let end = try #require(compact.last)
    #expect(abs(end.x - 14) < 0.01 && abs(end.y - 12) < 0.01)
  }

  @Test("parses the revised curled triangle")
  func curledTriangle() throws {
    let source = try #require(SymbolCatalog.bundled.symbol(id: "c:curled-triangle")?.path)
    #expect(source == "M12 3 L22 21 H2 Z M7 18 Q15 19 15 15 Q15 11 12 12 Q10 13 12 15")
    let bounds = try #require(SymbolPath.parse(source)).boundingRect
    #expect(bounds.minX == 2 && bounds.maxX == 22 && bounds.minY == 3 && bounds.maxY == 21)
    #expect(try points(source).last == CGPoint(x: 12, y: 15))
  }

  @Test("rejects commands outside the contract and malformed data", arguments: [
    "", "L1 1", "M1", "M1 2S3 4 5 6", "M1 2T3 4", "M1 2L3", "M1 2 a5 5 0 2 0 1 1", "M1 2x",
  ])
  func rejects(source: String) {
    #expect(SymbolPath.parse(source) == nil)
  }
}

@MainActor
@Suite("Symbol glyph coverage")
struct SymbolGlyphCoverageTests {

  @Test("system fonts cover the rare catalog glyphs", arguments: ["ᴥ", "ꭓ", "ψ", "♪", "♥", "✔", "♀", "❄", "☀", "▶", "♥\u{FE0E}", "♥\u{FE0F}"])
  func coversRareGlyphs(text: String) {
    #expect(SymbolGlyphCoverage.isRenderable(text))
  }

  // Measured on the iOS 26 simulator: only LastResort has U+A728, so it uses the
  // code point fallback. Revisit if a later iOS adds coverage.
  @Test("Tz falls back to its code point label")
  func tzFallsBack() {
    #expect(!SymbolGlyphCoverage.isRenderable("Ꜩ"))
    #expect(SymbolGlyphCoverage.fallbackLabel(for: "u:A728") == "U+A728")
  }

  @Test("display text requests text presentation for non-ASCII emoji-capable code points")
  func displayTextPresentation() {
    #expect(ColorKeySymbol.displayText("♥") == "♥\u{FE0E}")
    #expect(ColorKeySymbol.displayText("✔") == "✔\u{FE0E}")
    #expect(ColorKeySymbol.displayText("♥\u{FE0E}") == "♥\u{FE0E}")
    #expect(ColorKeySymbol.displayText("♥\u{FE0F}") == "♥\u{FE0F}")
    #expect(ColorKeySymbol.displayText("♀♂") == "♀\u{FE0E}♂\u{FE0E}")
    #expect(ColorKeySymbol.displayText("ψ") == "ψ")
    #expect(ColorKeySymbol.displayText("1") == "1")
    #expect(ColorKeySymbol.displayText("#") == "#")
  }

  @Test("IDs strip variation selectors")
  func idsStripSelectors() {
    #expect(ColorKeySymbol.unicodeID(for: "♥\u{FE0E}") == "u:2665")
    #expect(ColorKeySymbol.unicodeID(for: "♥\u{FE0F}") == "u:2665")
    #expect(ColorKeySymbol(id: "u:2665-FE0E")?.id == "u:2665")
  }
}
