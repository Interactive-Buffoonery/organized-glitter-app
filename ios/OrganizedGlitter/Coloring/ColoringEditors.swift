import SwiftUI

struct ColoringBookDraft: Equatable {
  var title: String
  var series: String
  var status: String
  var totalPages: Int
  var publisher: String
  var illustrator: String

  init(book: ColoringBookRecord? = nil) {
    title = book?.title ?? ""
    series = book?.series ?? ""
    status = book?.status ?? "purchased"
    totalPages = book?.totalPages ?? 1
    publisher = book?.publisher ?? ""
    illustrator = book?.illustrator ?? ""
  }

  var isValid: Bool {
    !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && totalPages >= 1
  }

  /// Deliberately ignores server-computed fields (`completedPages`,
  /// `completionPercentage`) and `coverImage`: the editor never writes them,
  /// so they cannot disagree with the draft.
  func matchesSavedRecord(_ record: ColoringBookRecord) -> Bool {
    title.trimmingCharacters(in: .whitespacesAndNewlines) == record.title
      && series.trimmingCharacters(in: .whitespacesAndNewlines) == (record.series ?? "")
      && status == record.status
      && totalPages == record.totalPages
      && publisher == (record.publisher ?? "")
      && illustrator == (record.illustrator ?? "")
  }
}

struct ColoringBookEditor: View {
  let client: PocketBaseClient
  let userID: String
  let book: ColoringBookRecord?
  let onLibraryRefresh: () async -> Void
  let onSaved: (ColoringBookRecord) -> Void

  private let baseline: ColoringBookDraft

  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @State private var draft: ColoringBookDraft
  @State private var isSaving = false
  @State private var errorMessage: String?
  @State private var isCompletionUnknown = false

  init(
    client: PocketBaseClient,
    userID: String,
    book: ColoringBookRecord? = nil,
    onLibraryRefresh: @escaping () async -> Void = {},
    onSaved: @escaping (ColoringBookRecord) -> Void
  ) {
    self.client = client
    self.userID = userID
    self.book = book
    self.onLibraryRefresh = onLibraryRefresh
    self.onSaved = onSaved
    let initialDraft = ColoringBookDraft(book: book)
    baseline = initialDraft
    _draft = State(initialValue: initialDraft)
  }

  var body: some View {
    NavigationStack {
      Form {
        if let book, let cover = book.coverImage?.nonEmpty {
          Section {
            AsyncImage(
              url: client.fileURL(
                collection: "coloring_books",
                recordID: book.id,
                filename: cover,
                thumb: "320x420"
              )
            ) { image in
              image
                .resizable()
                .scaledToFill()
            } placeholder: {
              RoundedRectangle(cornerRadius: Theme.Radius.medium)
                .fill(theme.muted)
                .overlay {
                  Image(systemName: "book.closed")
                    .foregroundStyle(theme.mutedForeground)
                }
            }
            .frame(width: 160, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
            .accessibilityLabel("Book cover")

            Text("Cover upload is coming soon.")
              .font(.footnote)
              .foregroundStyle(theme.mutedForeground)
          }
          .listRowBackground(theme.card)
        }

        Section("Book") {
          TextField("Title", text: $draft.title)
          TextField("Series", text: $draft.series)

          Picker("Status", selection: $draft.status) {
            ForEach(LibrarySection.books.statusOptions, id: \.self) { status in
              Text(status.organizedGlitterLabel).tag(status)
            }
          }

          TextField("Total pages", value: $draft.totalPages, format: .number)
            .keyboardType(.numberPad)
        }
        .listRowBackground(theme.card)

        Section("Credits") {
          TaxonomyPicker(
            client: client,
            userID: userID,
            collection: "book_publishers",
            label: "Publisher",
            initialName: book?.expand?.publisher?.name,
            selection: $draft.publisher
          )
          TaxonomyPicker(
            client: client,
            userID: userID,
            collection: "book_illustrators",
            label: "Illustrator",
            initialName: book?.expand?.illustrator?.name,
            selection: $draft.illustrator
          )
        }
        .listRowBackground(theme.card)

        if book != nil {
          Section {
            Text(
              "Changing the total updates the generated pages after save. Pages above the new total are removed only if you never touched them."
            )
            .font(.footnote)
            .foregroundStyle(theme.mutedForeground)
          }
          .listRowBackground(theme.card)
        }

        if let errorMessage {
          Section {
            AccessibleErrorLabel(message: errorMessage)
              .accessibilityIdentifier("bookSaveError")
          }
          .listRowBackground(theme.card)
        }
      }
      .themedScrollBackground()
      .navigationTitle(book == nil ? "New Coloring Book" : "Edit Coloring Book")
      .navigationBarTitleDisplayMode(.inline)
      .interactiveDismissDisabled(isSaving)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
          .disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            Task { await save() }
          }
          .disabled(!draft.isValid || isSaving || isCompletionUnknown)
        }
      }
    }
  }

  private func save() async {
    guard draft.isValid, !isSaving else {
      return
    }

    isSaving = true
    errorMessage = nil
    defer { isSaving = false }

    let write = ColoringBookWrite.make(
      userID: userID,
      baseline: baseline,
      draft: draft,
      isCreate: book == nil
    )

    do {
      let saved: ColoringBookRecord
      if let book {
        saved = try await client.update(
          collection: "coloring_books",
          id: book.id,
          body: write
        )
      } else {
        saved = try await client.create(collection: "coloring_books", body: write)
      }
      onSaved(saved)
      dismiss()
    } catch APIError.offline, APIError.server {
      await onLibraryRefresh()
      if let book,
        let refreshed: ColoringBookRecord = try? await client.get(
          collection: "coloring_books",
          id: book.id
        ),
        draft.matchesSavedRecord(refreshed)
      {
        onSaved(refreshed)
        dismiss()
        return
      }
      isCompletionUnknown = true
      errorMessage =
        "Save status is unknown. The library was refreshed; check the book before trying again."
    } catch {
      errorMessage = error.userMessage(
        permission: "Your account does not have permission to save this book.",
        fallback: "The book could not be saved. Try again."
      )
    }
  }
}

// `user` is sent only on create; it is omitted on update so a save can never
// reassign ownership. Every other field is omitted on update when unchanged
// because the synthesized encoder drops nil keys, and a PATCH without a key
// leaves the server value untouched. When the user clears series, publisher,
// or illustrator, the key is included as `""`, PocketBase's unset value for a
// non-required text or relation field.
struct ColoringBookWrite: Encodable {
  let user: String?
  let title: String?
  let series: String?
  let status: String?
  let totalPages: Int?
  let publisher: String?
  let illustrator: String?

  enum CodingKeys: String, CodingKey {
    case user, title, series, status, publisher, illustrator
    case totalPages = "total_pages"
  }

  static func make(
    userID: String,
    baseline: ColoringBookDraft,
    draft: ColoringBookDraft,
    isCreate: Bool
  ) -> ColoringBookWrite {
    let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedSeries = draft.series.trimmingCharacters(in: .whitespacesAndNewlines)
    if isCreate {
      return ColoringBookWrite(
        user: userID,
        title: trimmedTitle,
        series: trimmedSeries,
        status: draft.status,
        totalPages: draft.totalPages,
        publisher: draft.publisher,
        illustrator: draft.illustrator
      )
    }

    let baselineTitle = baseline.title.trimmingCharacters(in: .whitespacesAndNewlines)
    return ColoringBookWrite(
      user: nil,
      title: trimmedTitle != baselineTitle ? trimmedTitle : nil,
      series: trimmedSeries != baseline.series ? trimmedSeries : nil,
      status: draft.status != baseline.status ? draft.status : nil,
      totalPages: draft.totalPages != baseline.totalPages ? draft.totalPages : nil,
      publisher: draft.publisher != baseline.publisher ? draft.publisher : nil,
      illustrator: draft.illustrator != baseline.illustrator ? draft.illustrator : nil
    )
  }
}

struct ColoringPageDraft: Equatable {
  var status: String
  var revealedSubject: String

  init(page: ColoringPageRecord) {
    status = page.status
    revealedSubject = page.revealedSubject ?? ""
  }

  func matchesSavedRecord(_ record: ColoringPageRecord) -> Bool {
    status == record.status
      && revealedSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        == (record.revealedSubject ?? "")
  }
}

struct ColoringPageEditor: View {
  let client: PocketBaseClient
  let page: ColoringPageRecord
  let onLibraryRefresh: () async -> Void
  let onSaved: (ColoringPageRecord) -> Void

  private let baseline: ColoringPageDraft

  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @State private var draft: ColoringPageDraft
  @State private var isSaving = false
  @State private var errorMessage: String?
  @State private var isCompletionUnknown = false

  init(
    client: PocketBaseClient,
    page: ColoringPageRecord,
    onLibraryRefresh: @escaping () async -> Void = {},
    onSaved: @escaping (ColoringPageRecord) -> Void
  ) {
    self.client = client
    self.page = page
    self.onLibraryRefresh = onLibraryRefresh
    self.onSaved = onSaved
    let initialDraft = ColoringPageDraft(page: page)
    baseline = initialDraft
    _draft = State(initialValue: initialDraft)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Page \(page.pageNumber)") {
          if let photo = page.photos.first {
            AsyncImage(
              url: client.fileURL(
                collection: "coloring_pages",
                recordID: page.id,
                filename: photo,
                thumb: "160x160"
              )
            ) { image in
              image
                .resizable()
                .scaledToFill()
            } placeholder: {
              RoundedRectangle(cornerRadius: Theme.Radius.medium)
                .fill(theme.muted)
                .overlay {
                  Image(systemName: "doc.richtext")
                    .foregroundStyle(theme.mutedForeground)
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
            .accessibilityLabel("Page photo")
          }

          LabeledContent("Book", value: page.expand?.book?.title ?? "Unknown book")
        }
        .listRowBackground(theme.card)

        Section {
          Picker("Status", selection: $draft.status) {
            ForEach(LibrarySection.pages.statusOptions, id: \.self) { status in
              Text(status.organizedGlitterLabel).tag(status)
            }
          }

          TextField("Revealed subject", text: $draft.revealedSubject)

          Text("Started and completed dates are set automatically from status.")
            .font(.footnote)
            .foregroundStyle(theme.mutedForeground)
        }
        .listRowBackground(theme.card)

        if let errorMessage {
          Section {
            AccessibleErrorLabel(message: errorMessage)
              .accessibilityIdentifier("pageSaveError")
          }
          .listRowBackground(theme.card)
        }
      }
      .themedScrollBackground()
      .navigationTitle("Edit Page")
      .navigationBarTitleDisplayMode(.inline)
      .interactiveDismissDisabled(isSaving)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
          .disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            Task { await save() }
          }
          .disabled(isSaving || isCompletionUnknown)
        }
      }
    }
  }

  private func save() async {
    guard !isSaving else {
      return
    }

    isSaving = true
    errorMessage = nil
    defer { isSaving = false }

    let write = ColoringPageWrite.make(baseline: baseline, draft: draft)

    do {
      let saved: ColoringPageRecord = try await client.update(
        collection: "coloring_pages",
        id: page.id,
        body: write
      )
      onSaved(saved)
      dismiss()
    } catch APIError.offline, APIError.server {
      await onLibraryRefresh()
      if let refreshed: ColoringPageRecord = try? await client.get(
        collection: "coloring_pages",
        id: page.id
      ),
        draft.matchesSavedRecord(refreshed)
      {
        onSaved(refreshed)
        dismiss()
        return
      }
      isCompletionUnknown = true
      errorMessage =
        "Save status is unknown. The library was refreshed; check the page before trying again."
    } catch {
      errorMessage = error.userMessage(
        permission: "Your account does not have permission to save this page.",
        fallback: "The page could not be saved. Try again."
      )
    }
  }
}

// Never includes `user` or `book` keys: pages are created by the server when a
// book's total changes, and ownership flows through the book relation. The
// server hook manages `started_at`/`completed_at` from status transitions, so
// the client only ever writes status and the revealed subject. Unchanged
// fields are nil so the encoder omits the key and PATCH leaves them alone;
// clearing the subject sends `""`.
struct ColoringPageWrite: Encodable {
  let status: String?
  let revealedSubject: String?

  enum CodingKeys: String, CodingKey {
    case status
    case revealedSubject = "revealed_subject"
  }

  static func make(
    baseline: ColoringPageDraft,
    draft: ColoringPageDraft
  ) -> ColoringPageWrite {
    let trimmedSubject = draft.revealedSubject.trimmingCharacters(in: .whitespacesAndNewlines)
    return ColoringPageWrite(
      status: draft.status != baseline.status ? draft.status : nil,
      revealedSubject: trimmedSubject != baseline.revealedSubject ? trimmedSubject : nil
    )
  }
}
