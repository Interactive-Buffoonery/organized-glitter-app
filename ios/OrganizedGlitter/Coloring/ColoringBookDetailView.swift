import SwiftUI

struct ColoringBookDetailView: View {
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.theme) private var theme

  let book: ColoringBookRecord
  let model: LibraryItemDetailModel
  let onEditPageCount: () -> Void
  let onCollectionChanged: @MainActor @Sendable () async -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        bookHeader

        DetailStatusMenu<BookStatus>(current: book.status) { status in
          Task {
            let changed = await model.setStatus(status)
            if changed || (model.unresolvedStatusWrite && model.unresolvedWriteState == .refreshed) {
              await onCollectionChanged()
            }
          }
        }
        .controlSize(.large)
        .disabled(model.isMutating || model.unresolvedWriteState != nil)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 360)
        .frame(maxWidth: .infinity)
        DetailStatusRecovery(model: model, onCollectionChanged: onCollectionChanged)

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
          LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
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

        if let mutationErrorMessage = model.mutationErrorMessage,
          !model.unresolvedStatusWrite
        {
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

  private var bookHeader: some View {
    VStack(spacing: 8) {
      CoverArtwork(
        item: .book(book),
        url: LibraryItem.book(book).artworkURL(using: model.client, token: protectedFiles?.token),
        maxPixelDimension: 900,
        loadedAccessibilityLabel: "Book cover"
      )
      .frame(width: horizontalSizeClass == .regular ? 240 : 180)
      .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
      .padding(.bottom, 8)
      .accessibilityIdentifier("detail.hero")

      Text(book.title)
        .font(.title2.bold())
        .foregroundStyle(theme.foreground)
        .accessibilityAddTraits(.isHeader)
      if let credits = credits {
        Text(credits)
          .foregroundStyle(theme.pageSecondaryForeground)
      }
      Text("\(book.completedPages ?? 0) of \(book.totalPages) pages")
        .font(.subheadline)
        .foregroundStyle(theme.pageSecondaryForeground)
      ProgressView(
        value: min(max(book.completionPercentage ?? 0, 0), 100),
        total: 100
      )
      .frame(maxWidth: 240)
      .accessibilityLabel("Book completion")
      .accessibilityValue("\(book.completedPages ?? 0) of \(book.totalPages) pages")
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
  }

  private var credits: String? {
    [book.series, book.expand?.publisher?.name, book.expand?.illustrator?.name]
      .compactMap { $0?.nonEmpty }
      .joined(separator: " · ")
      .nonEmpty
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
      return Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
    }
    if horizontalSizeClass == .regular {
      return [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 10)]
    }
    return Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
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

/// A contact-sheet cell: the page, its number, and a status glyph.
private struct ColoringBookPageCard: View {
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.theme) private var theme

  let page: ColoringPageRecord
  let client: PocketBaseClient

  var body: some View {
    VStack(spacing: 4) {
      CoverArtwork(
        item: .page(page),
        url: LibraryItem.page(page).artworkURL(
          using: client, thumb: ArtworkThumb.gallery, token: protectedFiles?.token)
      )

      HStack(spacing: 3) {
        Text(page.pageNumber, format: .number)
          .monospacedDigit()
        if PageStatus(rawValue: page.status) != .notStarted {
          Image(systemName: PageStatus.systemImage(for: page.status))
            .foregroundStyle(theme.primary)
        }
      }
      .font(.caption)
      .foregroundStyle(theme.pageSecondaryForeground)
    }
    .frame(maxWidth: .infinity)
    .contentShape(.rect)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
  }

  private var accessibilityLabel: String {
    [
      "Page \(page.pageNumber)",
      page.revealedSubject?.nonEmpty,
      PageStatus.label(for: page.status),
    ].compactMap { $0 }.joined(separator: ", ")
  }
}
