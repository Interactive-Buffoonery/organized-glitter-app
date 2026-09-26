import SwiftUI

/// Every cover in the app: a 4:5 frame, filled and clipped. Records without an
/// upload, or whose image fails, get a generated cover seeded by record id.
struct CoverArtwork: View {
  @Environment(\.theme) private var theme

  let item: LibraryItem
  let url: URL?
  var maxPixelDimension: CGFloat = 660
  /// Set on heroes so UI tests and VoiceOver can tell a loaded upload apart.
  var loadedAccessibilityLabel: String?

  var body: some View {
    Color.clear
      .aspectRatio(4 / 5, contentMode: .fit)
      .overlay {
        RemoteArtwork(url: url, maxPixelDimension: maxPixelDimension) { phase in
          switch phase {
          case .success(let image):
            loaded(image)
          case .empty where url != nil:
            theme.muted
          default:
            GeneratedCover(item: item)
          }
        }
      }
      .clipShape(.rect(cornerRadius: Theme.Radius.medium))
  }

  @ViewBuilder
  private func loaded(_ image: Image) -> some View {
    let image = image.resizable().scaledToFill()
    if let loadedAccessibilityLabel {
      image
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loadedAccessibilityLabel)
    } else {
      image.accessibilityHidden(true)
    }
  }
}

/// A Berry Cream gradient, the title in Caveat, and a small craft glyph,
/// the way Apple Books covers a book without artwork.
struct GeneratedCover: View {
  let item: LibraryItem

  static let palettes: [(Color, Color)] = [
    (Color(hex: 0xFBD0DD), Color(hex: 0xE58BB0)),  // strawberry to raspberry
    (Color(hex: 0xECD6FA), Color(hex: 0xB692E8)),  // lilac to violet
    (Color(hex: 0xFDE3CF), Color(hex: 0xF2A3B3)),  // peach to rose
    (Color(hex: 0xD3DEFB), Color(hex: 0xC4A7F0)),  // periwinkle to lilac
    (Color(hex: 0xFDEAB8), Color(hex: 0xF4B6C9)),  // butter to blush
    (Color(hex: 0xCDEEDD), Color(hex: 0xA9C8EE)),  // mint to sky
  ]

  /// FNV-1a, because `Hasher` is seeded per launch and covers must not shuffle.
  static func paletteIndex(for seed: String) -> Int {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in seed.utf8 {
      hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
    }
    return Int(hash % UInt64(palettes.count))
  }

  var body: some View {
    let (top, bottom) = Self.palettes[Self.paletteIndex(for: item.id)]
    GeometryReader { geo in
      VStack(alignment: .leading) {
        Image(systemName: item.section.systemImage)
          .font(.system(size: geo.size.width * 0.1, weight: .semibold))
        Spacer(minLength: 0)
        // Caveat's final stroke can extend beyond the measured text width.
        Text(item.title + "\u{2002}")
          .font(.custom("Caveat", fixedSize: geo.size.width * 0.17))
          .lineLimit(4)
          .minimumScaleFactor(0.6)
      }
      .foregroundStyle(Color(hex: 0x46323E))
      .padding(geo.size.width * 0.09)
      .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
    }
    .background(LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
    .accessibilityHidden(true)
  }
}
