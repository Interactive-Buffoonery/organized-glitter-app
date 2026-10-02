import SwiftUI

struct LibraryGalleryCard: View {
  @Environment(\.theme) private var theme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let item: LibraryItem
  let imageURL: URL?
  var mode: LibraryViewMode = .covers
  /// Shelves and status filters already name the status.
  var showsStatus = true

  var body: some View {
    let metadata = LibraryItemMetadata(item: item)
    Group {
      if mode == .list {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: 8) {
            artwork.frame(width: 52)
            listText(metadata)
          }
        } else {
          HStack(alignment: .center, spacing: 10) {
            artwork.frame(width: 52)
            listText(metadata)
          }
        }
      } else {
        VStack(alignment: .leading, spacing: mode == .compact ? 4 : 8) {
          artwork
          Text(item.title)
            .font(.karla(mode == .compact ? .caption : .headline).weight(.semibold))
          if mode == .covers {
            metadataText(metadata.maker)
            if !metadata.specifications.isEmpty {
              metadataText(metadata.specifications)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
            }
          }
          if showsStatus {
            LibraryItemStatus(item: item, compact: mode == .compact)
          }
          if mode == .compact {
            metadataText(metadata.lifecycle.isEmpty ? metadata.specifications : metadata.lifecycle)
          }
        }
      }
    }
    .foregroundStyle(theme.foreground)
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(metadata.accessibilityLabel(for: item))
  }

  private var artwork: some View {
    CoverArtwork(item: item, url: imageURL)
  }

  private func listText(_ metadata: LibraryItemMetadata) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(item.title).font(.karla(.subheadline).weight(.semibold))
          Spacer(minLength: 0)
          if showsStatus { LibraryItemStatus(item: item) }
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(item.title).font(.karla(.subheadline).weight(.semibold))
          if showsStatus { LibraryItemStatus(item: item) }
        }
      }
      metadataText(metadata.maker)
      metadataText(metadata.detailLine)
    }
  }

  @ViewBuilder
  private func metadataText(_ value: String) -> some View {
    if !value.isEmpty {
      Text(value)
        .font(.karla(.caption))
        .foregroundStyle(theme.pageSecondaryForeground)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct LibraryItemStatus: View {
  @Environment(\.colorScheme) private var colorScheme
  let item: LibraryItem
  var compact = false

  var body: some View {
    let palette = DetailStatusAppearance.palette(for: item.status, colorScheme: colorScheme)
    Text("\(Text(Image(systemName: compact ? "circle.fill" : item.statusSystemImage))) \(item.statusLabel)")
      .font(.karla(.caption2).weight(.semibold))
      .foregroundStyle(compact
        ? DetailStatusAppearance.hue(for: item.status, colorScheme: colorScheme)
        : palette.foreground)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, compact ? 0 : 6)
      .padding(.vertical, compact ? 0 : 3)
      .background(compact ? Color.clear : palette.background, in: .capsule)
  }
}
