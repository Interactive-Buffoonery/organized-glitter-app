import SwiftUI

/// The stacked Caveat wordmark and its sparkles, drawn from plain colors.
///
/// Kept free of UIKit and `Theme` so `script/render-launch-wordmark.swift`
/// compiles this same file to draw the launch screen PNG. The static launch
/// image and the live wordmark then share one layout and can't drift.
///
/// Caveat's ascenders sit outside SwiftUI's default line box. Pad each line
/// instead of drawing through UIViewRepresentable — that representable
/// invalidated layout during the Continue with email push and crashed the
/// signed-out stack.
struct BrandWordmarkArt: View {
  enum Sparkles {
    case none
    case still
    case twinkling
  }

  let size: CGFloat
  let foreground: Color
  let primary: Color
  let accent: Color
  var sparkles: Sparkles = .none

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: size * 0.08) {
      line("Organized")
      line("Glitter")
    }
    .overlay {
      if sparkles != .none {
        // Offsets and diameters are in units of `size`, measured from the
        // wordmark's center, so the sparkles scale with Dynamic Type.
        sparkle(primary, diameter: 0.44, x: 1.83, y: -1.55, speed: 0.8)
        sparkle(accent, diameter: 0.31, x: -1.42, y: 1.02, speed: 1)
        sparkle(primary, diameter: 0.2, x: 1.34, y: 0.15, speed: 1.25)
      }
    }
  }

  private func line(_ text: String) -> some View {
    Text(text + "\u{2002}")
      .font(.custom("Caveat", fixedSize: size))
      .foregroundStyle(foreground)
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .padding(.horizontal, size * 0.08)
      .padding(.vertical, size * 0.22)
  }

  private func sparkle(
    _ color: Color, diameter: CGFloat, x: CGFloat, y: CGFloat, speed: Double
  ) -> some View {
    Image(systemName: "sparkle")
      .resizable()
      .scaledToFit()
      .frame(width: size * diameter, height: size * diameter)
      .foregroundStyle(color)
      .symbolEffect(
        .breathe, options: .speed(speed), isActive: sparkles == .twinkling && !reduceMotion
      )
      .offset(x: size * x, y: size * y)
      .accessibilityHidden(true)
  }
}
