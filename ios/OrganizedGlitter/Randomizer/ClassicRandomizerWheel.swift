import SwiftUI

struct ClassicRandomizerWheel: View {
  @Environment(\.theme) private var theme
  let candidates: [RandomizerCandidate]
  let rotation: Double
  let winnerIndex: Int?

  var body: some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let radius = min(size.width, size.height) / 2 - 2
      let count = candidates.count
      guard count > 0 else {
        context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
          width: radius * 2, height: radius * 2)), with: .color(theme.card))
        return
      }
      for (index, candidate) in candidates.enumerated() {
        let start = Double(index) * 360 / Double(count)
        let end = Double(index + 1) * 360 / Double(count)
        var wedge = Path()
        if count == 1 {
          wedge.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2))
        } else {
          wedge.move(to: center)
          wedge.addArc(center: center, radius: radius, startAngle: .degrees(start),
            endAngle: .degrees(end), clockwise: false)
          wedge.closeSubpath()
        }
        let palette = Self.palette(for: candidate.id)
        context.fill(wedge, with: .color(Color(hex: palette.background)))
        context.stroke(wedge, with: .color(theme.border), lineWidth: 1)
        let angle = (start + end) / 2 * .pi / 180
        let position = CGPoint(x: center.x + cos(angle) * radius * 0.67,
          y: center.y + sin(angle) * radius * 0.67)
        let label = Text(String(index + 1))
          .font(.custom("Karla-Regular", size: max(8, min(22, 160 / Double(count)))))
          .foregroundColor(Color(hex: palette.foreground))
        context.draw(label, at: position)
      }
    }
    .rotationEffect(.degrees(rotation))
    .overlay {
      Circle()
        .fill(theme.card)
        .overlay { Circle().stroke(theme.border, lineWidth: 2) }
        .frame(width: 56, height: 56)
        .overlay {
          if let winnerIndex = winnerIndex ?? (candidates.count == 1 ? 0 : nil) {
            Text(String(winnerIndex + 1))
              .font(.karla(.title2).weight(.semibold))
              .foregroundStyle(theme.foreground)
          } else {
            Image(systemName: "sparkles")
              .foregroundStyle(theme.pageAction)
          }
        }
    }
    .overlay(alignment: .top) {
      Image(systemName: "arrowtriangle.down.fill")
        .font(.system(size: 24, weight: .bold))
        .foregroundStyle(theme.foreground)
        .offset(y: -9)
    }
    .aspectRatio(1, contentMode: .fit)
    .frame(maxWidth: 320)
    .padding(.top, 10)
    .accessibilityHidden(true)
  }

  private static let backgrounds: [UInt32] = [
    0xB99AE8, 0xFFF4DF, 0x8054B3, 0xE4D5F5, 0xF5EAD8, 0xA47BD4,
    0xD1B8EE, 0xFFF9EE, 0x69428F, 0xECE2F7, 0xC4A5E5, 0xF0E4D2,
  ]

  private static func palette(for key: LocalRecordKey) -> (background: UInt32, foreground: UInt32) {
    let hash = key.id.utf16.reduce(UInt32(0)) { ($0 &* 31) &+ UInt32($1) }
    let background = backgrounds[Int(hash % UInt32(backgrounds.count))]
    let foreground: UInt32 = [0x8054B3, 0x69428F].contains(background)
      ? 0xFFFFFF : 0x211827
    return (background, foreground)
  }
}

extension Theme {
  static let randomizerSpin = Animation.timingCurve(0, 0, 0.58, 1, duration: 3)
}
