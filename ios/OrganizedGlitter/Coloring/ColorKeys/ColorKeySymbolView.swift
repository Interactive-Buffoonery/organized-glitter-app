import SwiftUI

/// Draws one color key symbol in a square of `size` points.
struct ColorKeySymbolView: View {
  @Environment(\.theme) private var theme

  let id: String
  var size: CGFloat = 44
  /// The 96x96f thumbnail for an `r:` symbol request.
  var requestThumbnailURL: URL? = nil
  var catalog: SymbolCatalog = .bundled

  var body: some View {
    content
      .frame(width: size, height: size)
      .accessibilityElement()
      .accessibilityLabel(catalog.accessibilityName(for: id))
  }

  @ViewBuilder
  private var content: some View {
    switch ColorKeySymbol(id: id) {
    case .unicode(let text) where SymbolGlyphCoverage.isRenderable(text):
      Text(verbatim: ColorKeySymbol.displayText(text))
        .font(.system(size: size * 0.78))
        .minimumScaleFactor(0.3)
        .lineLimit(1)
        .foregroundStyle(theme.foreground)
    case .unicode:
      placeholder(label: SymbolGlyphCoverage.fallbackLabel(for: id))
    case .custom(let slug):
      if let source = catalog.symbol(id: "c:\(slug)")?.path, let path = SymbolPath.parse(source) {
        SymbolShape(path: path)
          .stroke(
            theme.foreground,
            style: StrokeStyle(lineWidth: size / 12, lineCap: .round, lineJoin: .round))
      } else {
        placeholder(label: nil)
      }
    case .request:
      RemoteArtwork(url: requestThumbnailURL, maxPixelDimension: 96) { phase in
        if case .success(let image) = phase {
          image.resizable().scaledToFill().clipShape(.rect(cornerRadius: size / 8))
        } else {
          placeholder(label: nil, systemImage: "photo")
        }
      }
    case nil:
      placeholder(label: nil)
    }
  }

  private func placeholder(label: String?, systemImage: String = "questionmark") -> some View {
    RoundedRectangle(cornerRadius: size / 8)
      .strokeBorder(theme.mutedForeground, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
      .overlay {
        if let label {
          Text(verbatim: label)
            .font(.system(size: size * 0.22).monospaced())
            .minimumScaleFactor(0.5)
            .multilineTextAlignment(.center)
            .padding(2)
        } else {
          Image(systemName: systemImage)
            .font(.system(size: size * 0.4))
        }
      }
      .foregroundStyle(theme.mutedForeground)
  }
}

/// Scales a 24x24 catalog path to fill its frame.
private struct SymbolShape: Shape {
  let path: Path

  func path(in rect: CGRect) -> Path {
    let scale = min(rect.width, rect.height) / 24
    return path.applying(
      CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale))
  }
}

#Preview {
  let ids = ["u:03C8", "u:1D25", "u:A728", "u:AB53", "u:2603", "u:0378", "c:linked-circles",
    "c:wave", "c:leaf", "c:curled-triangle", "c:plus-box", "c:missing", "r:abc123def456ghi"]
  LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))]) {
    ForEach(ids, id: \.self) { ColorKeySymbolView(id: $0, size: 56) }
  }
  .padding()
}
