import SwiftUI

struct ColoringBookDetailView: View {
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.theme) private var theme

  let book: ColoringBookRecord
  let model: LibraryItemDetailModel
  let onEditPageCount: () -> Void
  let onCollectionChanged: @MainActor @Sendable () async -> Void

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        bookHeader

        pagesHeader

        if dynamicTypeSize.isAccessibilitySize {
          pageFilterPicker
            .pickerStyle(.menu)
        } else {
          pageFilterPicker
            .pickerStyle(.segmented)
        }

        if model.bookPages.isEmpty, !model.isLoading, model.errorMessage == nil {
          ContentUnavailableView(
            "No matching pages",
            systemImage: "doc.richtext",
            description: Text(emptyPagesMessage)
          )
          .frame(maxWidth: .infinity)
        } else {
          LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(model.bookPages) { page in
              NavigationLink {
                LibraryItemDetailDestination(
                  item: .page(page),
                  client: model.client,
                  userID: model.userID,
                  onCollectionChanged: {
                    model.needsBookPageRefresh = true
                    await onCollectionChanged()
                  }
                )
              } label: {
                ColoringBookPageCard(page: page, client: model.client)
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("detail.book.page.\(page.id)")
            }
          }
          .accessibilityIdentifier("detail.book.pages")
        }

        if model.canLoadMoreBookPages {
          Button {
            Task { await model.loadMoreBookPages() }
          } label: {
            HStack {
              if model.isLoadingMore {
                ProgressView()
              }
              Text(model.isLoadingMore ? "Loading more pages" : "Load more pages")
            }
            .frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(.bordered)
          .disabled(model.isLoadingMore)
          .accessibilityLabel(
            model.isLoadingMore ? "Loading more pages" : "Load more pages"
          )
          .accessibilityIdentifier("detail.book.loadMore")
        }

        if book.expand?.publisher?.name.nonEmpty != nil
          || book.expand?.illustrator?.name.nonEmpty != nil
        {
          VStack(alignment: .leading, spacing: 12) {
            Text("Book details")
              .font(.title3.weight(.semibold))
              .foregroundStyle(theme.foreground)
              .accessibilityAddTraits(.isHeader)
            DetailMetadataCard {
              if let publisher = book.expand?.publisher?.name.nonEmpty {
                DetailMetadataRow(label: "Publisher", value: publisher)
              }
              if let illustrator = book.expand?.illustrator?.name.nonEmpty {
                DetailMetadataRow(label: "Illustrator", value: illustrator)
              }
            }
          }
        }

        if let errorMessage = model.errorMessage {
          VStack(alignment: .leading, spacing: 12) {
            AccessibleErrorLabel(message: errorMessage)
            Button("Try again") {
              Task { await model.load() }
            }
          }
        }

        if let mutationErrorMessage = model.mutationErrorMessage {
          AccessibleErrorLabel(message: mutationErrorMessage)
        }
      }
      .frame(maxWidth: 760, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.vertical, 16)
      .frame(maxWidth: .infinity)
    }
    .background {
      theme.themedBackground.ignoresSafeArea()
    }
    .refreshable { await model.load() }
  }

  @ViewBuilder
  private var bookHeader: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 16))

    layout {
      RecordArtwork(
        url: LibraryItem.book(book).artworkURL(
          using: model.client, thumb: ArtworkThumb.gallery, token: protectedFiles?.token),
        maxHeight: 150,
        emptyMinHeight: 150,
        maxPixelDimension: 360,
        successAccessibilityLabel: "Book cover"
      )
      .frame(
        width: dynamicTypeSize.isAccessibilitySize ? nil : 112,
        height: 150
      )
      .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
      .clipShape(.rect(cornerRadius: Theme.Radius.medium))
      .accessibilityIdentifier("detail.hero")

      VStack(alignment: .leading, spacing: 8) {
        Text(book.title)
          .font(.title2.bold())
          .foregroundStyle(theme.foreground)
        if let series = book.series?.nonEmpty {
          Text(series)
            .foregroundStyle(theme.pageSecondaryForeground)
        }
        Text("Coloring book")
          .font(.subheadline)
          .foregroundStyle(theme.pageSecondaryForeground)
        StatusBadge(status: book.status, presentation: .quiet)
        Text("\(book.completedPages ?? 0) of \(book.totalPages) pages")
          .font(.subheadline)
          .foregroundStyle(theme.pageSecondaryForeground)
        ProgressView(
          value: min(max(book.completionPercentage ?? 0, 0), 100),
          total: 100
        )
        .accessibilityLabel("Book completion")
        .accessibilityValue("\(book.completedPages ?? 0) of \(book.totalPages) pages")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var emptyPagesMessage: String {
    if model.bookPageFilter == .all {
      "Edit the page count to generate pages for this book."
    } else {
      "No pages have the \(model.bookPageFilter.title.lowercased()) status."
    }
  }

  private var columns: [GridItem] {
    if dynamicTypeSize.isAccessibilitySize {
      return [GridItem(.flexible())]
    }
    return [GridItem(.adaptive(minimum: 142, maximum: 220), spacing: 14)]
  }

  private var pageFilterPicker: some View {
    Picker(
      "Page status",
      selection: Binding(
        get: { model.bookPageFilter },
        set: { filter in
          Task { await model.setBookPageFilter(filter) }
        }
      )
    ) {
      ForEach(BookPageFilter.allCases) { filter in
        Text(filter.title).tag(filter)
      }
    }
    .accessibilityIdentifier("detail.book.filter")
  }

  @ViewBuilder
  private var pagesHeader: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 8) {
        pagesTitle
        editPageCountButton
      }
    } else {
      HStack(alignment: .firstTextBaseline) {
        pagesTitle
        Spacer()
        editPageCountButton
      }
    }
  }

  private var pagesTitle: some View {
    Text("Pages")
      .font(.title3.weight(.semibold))
      .foregroundStyle(theme.foreground)
      .accessibilityAddTraits(.isHeader)
  }

  private var editPageCountButton: some View {
    Button {
      onEditPageCount()
    } label: {
      Label("Edit page count", systemImage: "number")
    }
    .buttonStyle(.bordered)
    .accessibilityIdentifier("detail.book.editPageCount")
  }
}

private struct ColoringBookPageCard: View {
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.theme) private var theme

  let page: ColoringPageRecord
  let client: PocketBaseClient

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      RecordArtwork(
        url: LibraryItem.page(page).artworkURL(
          using: client, thumb: ArtworkThumb.gallery, token: protectedFiles?.token),
        maxHeight: 220,
        emptyMinHeight: 150,
        maxPixelDimension: 660
      )
      .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 220)
      .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
      .clipShape(.rect(cornerRadius: Theme.Radius.medium))
      .accessibilityHidden(true)

      Text(LibraryItem.page(page).title)
        .font(.headline)
        .foregroundStyle(theme.foreground)
        .fixedSize(horizontal: false, vertical: true)
      StatusBadge(status: page.status, presentation: .quiet)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
  }
}
