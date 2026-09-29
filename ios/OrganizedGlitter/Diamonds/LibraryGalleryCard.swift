import SwiftUI

struct LibraryGalleryCard: View {
  @Environment(\.theme) private var theme

  let item: LibraryItem
  let imageURL: URL?
  /// Shelves and status filters already name the status.
  var showsStatus = true

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      CoverArtwork(item: item, url: imageURL)

      Text(item.title)
        .font(.headline)
        .foregroundStyle(theme.foreground)
        .fixedSize(horizontal: false, vertical: true)

      if !item.galleryCaption.isEmpty {
        Text(item.galleryCaption)
          .font(.subheadline)
          .foregroundStyle(theme.pageSecondaryForeground)
          .fixedSize(horizontal: false, vertical: true)
      }

      if showsStatus {
        StatusBadge(label: item.statusLabel, systemImage: item.statusSystemImage)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
  }
}

extension LibraryItem {
  var galleryCaption: String {
    switch self {
    case .diamond:
      return ""
    case .book(let book):
      return "\(book.totalPages) \(book.totalPages == 1 ? "page" : "pages")"
    case .page:
      return libraryCaption
    }
  }
}
