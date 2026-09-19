import SwiftUI

struct LibraryGalleryCard: View {
  @Environment(\.theme) private var theme

  let item: LibraryItem
  let imageURL: URL?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      RecordArtwork(
        url: imageURL,
        maxHeight: item.isColoringBook ? 260 : 230,
        emptyMinHeight: item.isColoringBook ? 220 : 170
      )
        .aspectRatio(item.isColoringBook ? 0.72 : 1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(theme.card, in: .rect(cornerRadius: 10))
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityHidden(true)

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

      StatusBadge(status: item.status, presentation: .quiet)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
  }
}

extension LibraryItem {
  fileprivate var isColoringBook: Bool {
    if case .book = self {
      return true
    }
    return false
  }

  var galleryCaption: String {
    if case .book(let book) = self {
      return "\(book.totalPages) \(book.totalPages == 1 ? "page" : "pages")"
    }
    return libraryCaption
  }
}
