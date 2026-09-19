import SwiftUI

struct LibraryGalleryCard: View {
  @Environment(\.theme) private var theme

  let item: LibraryItem
  let imageURL: URL?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      RecordArtwork(url: imageURL, maxHeight: 230, emptyMinHeight: 170)
        .frame(maxWidth: .infinity, minHeight: 170, maxHeight: 230)
        .background(theme.card, in: .rect(cornerRadius: 10))
        .accessibilityHidden(true)

      Text(item.title)
        .font(.headline)
        .foregroundStyle(theme.foreground)
        .fixedSize(horizontal: false, vertical: true)

      if !item.libraryCaption.isEmpty {
        Text(item.libraryCaption)
          .font(.subheadline)
          .foregroundStyle(theme.pageSecondaryForeground)
          .fixedSize(horizontal: false, vertical: true)
      }

      StatusBadge(status: item.status, presentation: .quiet)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
  }
}
