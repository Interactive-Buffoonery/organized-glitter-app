import SwiftUI

struct ColoringBookDetailView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.theme) private var theme

  let book: ColoringBookRecord
  let model: LibraryItemDetailModel
  let onEditPageCount: () -> Void

  private let columns = [
    GridItem(.adaptive(minimum: 142, maximum: 220), spacing: 14)
  ]

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 24) {
        bookHeader

        DetailMetadataCard {
          DetailMetadataRow(label: "Status") {
            StatusBadge(status: book.status, presentation: .quiet)
          }
          DetailMetadataRow(
            label: "Progress",
            value: "\(book.completedPages ?? 0) of \(book.totalPages) pages"
          )
          if let publisher = book.expand?.publisher?.name.nonEmpty {
            DetailMetadataRow(label: "Publisher", value: publisher)
          }
          if let illustrator = book.expand?.illustrator?.name.nonEmpty {
            DetailMetadataRow(label: "Illustrator", value: illustrator)
          }
        }

        VStack(alignment: .leading, spacing: 14) {
          HStack(alignment: .firstTextBaseline) {
            Text("Pages")
              .font(.title2.bold())
              .foregroundStyle(theme.foreground)
              .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
              onEditPageCount()
            } label: {
              Label("Edit page count", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("detail.book.editPageCount")
          }

          if dynamicTypeSize.isAccessibilitySize {
            pageFilterPicker
              .pickerStyle(.menu)
          } else {
            pageFilterPicker
              .pickerStyle(.segmented)
          }

          if model.bookPages.isEmpty, !model.isLoading {
            ContentUnavailableView(
              "No matching pages",
              systemImage: "doc.richtext",
              description: Text(emptyPagesMessage)
            )
            .frame(maxWidth: .infinity)
          } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
              ForEach(model.bookPages) { page in
                NavigationLink(value: LibraryItem.page(page)) {
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
              if model.isLoadingMore {
                ProgressView()
                  .frame(maxWidth: .infinity)
              } else {
                Text("Load more pages")
                  .frame(maxWidth: .infinity)
              }
            }
            .buttonStyle(.bordered)
            .disabled(model.isLoadingMore)
            .accessibilityIdentifier("detail.book.loadMore")
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
      .padding(16)
    }
    .background(theme.themedBackground)
    .refreshable { await model.load() }
  }

  @ViewBuilder
  private var bookHeader: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 18))

    layout {
      RecordArtwork(
        url: LibraryItem.book(book).artworkURL(using: model.client),
        maxHeight: 260,
        emptyMinHeight: 180
      )
      .frame(
        maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 160,
        minHeight: 180,
        maxHeight: 260
      )
      .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
      .clipShape(.rect(cornerRadius: Theme.Radius.medium))
      .accessibilityLabel("Book cover")
      .accessibilityIdentifier("detail.hero")

      VStack(alignment: .leading, spacing: 8) {
        Text(book.title)
          .font(.largeTitle.bold())
          .foregroundStyle(theme.foreground)
          .accessibilityAddTraits(.isHeader)
        if let series = book.series?.nonEmpty {
          Text(series)
            .foregroundStyle(theme.pageSecondaryForeground)
        }
        Text("Coloring book")
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
}

private struct ColoringBookPageCard: View {
  @Environment(\.theme) private var theme

  let page: ColoringPageRecord
  let client: PocketBaseClient

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      RecordArtwork(
        url: LibraryItem.page(page).artworkURL(using: client),
        maxHeight: 220,
        emptyMinHeight: 150
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
