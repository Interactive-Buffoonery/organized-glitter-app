import SwiftUI

enum AccountEntryLayout {
  static let topPadding: CGFloat = 24
  static let bottomPadding: CGFloat = 36
  static let primaryButtonHeight: CGFloat = 52
  static let secondaryButtonHeight: CGFloat = 48
  static let actionSpacing: CGFloat = 12
  static let actionsBottomPadding: CGFloat = 16
  static let welcomeWordmarkSize: CGFloat = 64

  static var launchWordmarkOffset: CGFloat {
    let actionsHeight = primaryButtonHeight + actionSpacing + secondaryButtonHeight
      + actionsBottomPadding
    return (topPadding - bottomPadding - actionsHeight) / 2
  }

  static var launchCanvas: CGSize {
    CGSize(
      width: welcomeWordmarkSize * 5,
      height: welcomeWordmarkSize * 4 + abs(launchWordmarkOffset) * 2
    )
  }
}

/// The stacked Caveat wordmark and its sparkles, drawn from plain colors.
///
/// Kept free of UIKit and `Theme` so `script/render-launch-wordmark.swift`
/// compiles this same file to draw the launch screen PNG. The static launch
/// image and the live wordmark share their artwork and base layout metrics.
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

  private struct SparkleGeometry {
    let diameter: CGFloat
    let x: CGFloat
    let y: CGFloat
    let speed: Double

    static let upperTrailing = Self(diameter: 0.44, x: 1.83, y: -1.55, speed: 0.8)
    static let lowerLeading = Self(diameter: 0.31, x: -1.42, y: 1.02, speed: 1)
    static let middleTrailing = Self(diameter: 0.2, x: 1.34, y: 0.15, speed: 1.25)
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
        sparkle(primary, geometry: .upperTrailing)
        sparkle(accent, geometry: .lowerLeading)
        sparkle(primary, geometry: .middleTrailing)
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
    _ color: Color, geometry: SparkleGeometry
  ) -> some View {
    Image(systemName: "sparkle")
      .resizable()
      .scaledToFit()
      .frame(width: size * geometry.diameter, height: size * geometry.diameter)
      .foregroundStyle(color)
      .symbolEffect(
        .breathe, options: .speed(geometry.speed), isActive: sparkles == .twinkling && !reduceMotion
      )
      .offset(x: size * geometry.x, y: size * geometry.y)
      .accessibilityHidden(true)
  }
}
