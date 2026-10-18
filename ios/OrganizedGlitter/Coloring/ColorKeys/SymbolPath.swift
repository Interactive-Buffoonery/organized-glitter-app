import CoreGraphics
import SwiftUI

/// Parses catalog shape paths on a 24x24 grid. The catalog only uses
/// M L H V C Q A Z, absolute or relative, so other SVG commands are rejected.
enum SymbolPath {
  static func parse(_ source: String) -> Path? {
    var scanner = Scanner(Array(source.utf8))
    var path = Path()
    var current = CGPoint.zero
    var start = CGPoint.zero
    var command: UInt8?
    var hasMove = false

    while true {
      scanner.skipSeparators()
      guard let next = scanner.peek else { break }
      if Self.commands.contains(next | 0x20) {
        command = next
        scanner.advance()
      } else if command == nil || command! | 0x20 == UInt8(ascii: "z") {
        return nil
      }
      guard let letter = command else { return nil }
      let relative = letter >= UInt8(ascii: "a")
      let origin = relative ? current : .zero
      func point() -> CGPoint? {
        guard let x = scanner.number(), let y = scanner.number() else { return nil }
        return CGPoint(x: origin.x + x, y: origin.y + y)
      }

      switch letter | 0x20 {
      case UInt8(ascii: "m"):
        guard let target = point() else { return nil }
        path.move(to: target)
        current = target
        start = target
        hasMove = true
        command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")
        continue
      case UInt8(ascii: "z"):
        guard hasMove else { return nil }
        path.closeSubpath()
        path.move(to: start)
        current = start
        command = nil
        continue
      default:
        guard hasMove else { return nil }
      }

      switch letter | 0x20 {
      case UInt8(ascii: "l"):
        guard let target = point() else { return nil }
        path.addLine(to: target)
        current = target
      case UInt8(ascii: "h"):
        guard let x = scanner.number() else { return nil }
        current = CGPoint(x: origin.x + x, y: current.y)
        path.addLine(to: current)
      case UInt8(ascii: "v"):
        guard let y = scanner.number() else { return nil }
        current = CGPoint(x: current.x, y: origin.y + y)
        path.addLine(to: current)
      case UInt8(ascii: "c"):
        guard let control1 = point(), let control2 = point(), let target = point() else {
          return nil
        }
        path.addCurve(to: target, control1: control1, control2: control2)
        current = target
      case UInt8(ascii: "q"):
        guard let control = point(), let target = point() else { return nil }
        path.addQuadCurve(to: target, control: control)
        current = target
      default:
        guard let rx = scanner.number(), let ry = scanner.number(),
          let rotation = scanner.number(), let largeArc = scanner.flag(),
          let sweep = scanner.flag(), let target = point()
        else { return nil }
        addArc(to: &path, from: current, to: target, radii: CGSize(width: rx, height: ry),
          rotation: rotation, largeArc: largeArc, sweep: sweep)
        current = target
      }
    }
    return hasMove ? path : nil
  }

  private static let commands = Set("mlhvcqaz".utf8)

  /// Converts an SVG endpoint arc to a center arc (SVG 1.1 implementation notes, F.6.5).
  private static func addArc(
    to path: inout Path, from p0: CGPoint, to p1: CGPoint, radii: CGSize,
    rotation degrees: CGFloat, largeArc: Bool, sweep: Bool
  ) {
    var rx = abs(radii.width)
    var ry = abs(radii.height)
    guard p0 != p1 else { return }
    guard rx > 0, ry > 0 else {
      path.addLine(to: p1)
      return
    }
    let phi = degrees * .pi / 180
    let cosPhi = cos(phi)
    let sinPhi = sin(phi)
    let dx = (p0.x - p1.x) / 2
    let dy = (p0.y - p1.y) / 2
    let x1 = cosPhi * dx + sinPhi * dy
    let y1 = -sinPhi * dx + cosPhi * dy
    let scale = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
    if scale > 1 {
      rx *= scale.squareRoot()
      ry *= scale.squareRoot()
    }
    let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
    var factor = (max(0, numerator) / denominator).squareRoot()
    if largeArc == sweep { factor = -factor }
    let cx1 = factor * rx * y1 / ry
    let cy1 = -factor * ry * x1 / rx
    let center = CGPoint(
      x: cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2,
      y: sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2)

    func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
      atan2(ux * vy - uy * vx, ux * vx + uy * vy)
    }
    let ux = (x1 - cx1) / rx
    let uy = (y1 - cy1) / ry
    let vx = (-x1 - cx1) / rx
    let vy = (-y1 - cy1) / ry
    let startAngle = angle(1, 0, ux, uy)
    var delta = angle(ux, uy, vx, vy)
    if !sweep, delta > 0 { delta -= 2 * .pi }
    if sweep, delta < 0 { delta += 2 * .pi }

    let transform = CGAffineTransform(translationX: center.x, y: center.y)
      .rotated(by: phi)
      .scaledBy(x: rx, y: ry)
    path.addRelativeArc(
      center: .zero, radius: 1, startAngle: .radians(startAngle), delta: .radians(delta),
      transform: transform)
  }

  private struct Scanner {
    let bytes: [UInt8]
    var index = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var peek: UInt8? { index < bytes.count ? bytes[index] : nil }

    mutating func advance() { index += 1 }

    mutating func skipSeparators() {
      while let byte = peek, byte == UInt8(ascii: ",") || byte == 0x20 || (0x09...0x0D).contains(byte) {
        advance()
      }
    }

    mutating func flag() -> Bool? {
      skipSeparators()
      switch peek {
      case UInt8(ascii: "0"): advance(); return false
      case UInt8(ascii: "1"): advance(); return true
      default: return nil
      }
    }

    mutating func number() -> CGFloat? {
      skipSeparators()
      let begin = index
      if peek == UInt8(ascii: "-") || peek == UInt8(ascii: "+") { advance() }
      var digits = 0
      var seenDot = false
      while let byte = peek {
        if (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) {
          digits += 1
        } else if byte == UInt8(ascii: "."), !seenDot {
          seenDot = true
        } else {
          break
        }
        advance()
      }
      guard digits > 0 else {
        index = begin
        return nil
      }
      if peek == UInt8(ascii: "e") || peek == UInt8(ascii: "E") {
        let exponentStart = index
        advance()
        if peek == UInt8(ascii: "-") || peek == UInt8(ascii: "+") { advance() }
        var exponentDigits = 0
        while let byte = peek, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) {
          exponentDigits += 1
          advance()
        }
        if exponentDigits == 0 { index = exponentStart }
      }
      return Double(String(decoding: bytes[begin..<index], as: UTF8.self)).map { CGFloat($0) }
    }
  }
}
