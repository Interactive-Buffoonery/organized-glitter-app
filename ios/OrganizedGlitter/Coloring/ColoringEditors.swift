import SwiftUI

struct ColoringBookDraft: Equatable {
  var title: String
  var series: String
  var status: String
  var totalPages: Int
  var publisher: String
  var illustrator: String
  var notes: String
  var isMystery: Bool
  var isbn: String
  var bookFormat: String
  var edition: String
  var publicationYear: Int?
  var language: String
  var theme: String
  var sourceURL: String
  var tags: Set<String>
  var datePurchased: Date?
  var dateReceived: Date?
  var dateStarted: Date?
  var dateCompleted: Date?

  init(book: ColoringBookRecord? = nil) {
    title = book?.title ?? ""
    series = book?.series ?? ""
    status = book?.status ?? "purchased"
    totalPages = book?.totalPages ?? 1
    publisher = book?.publisher ?? ""
    illustrator = book?.illustrator ?? ""
    notes = book?.notes ?? ""
    isMystery = book?.isMystery ?? false
    isbn = book?.isbn ?? ""
    bookFormat = book?.bookFormat ?? ""
    edition = book?.edition ?? ""
    publicationYear = book?.publicationYear.flatMap { $0 == 0 ? nil : $0 }
    language = book?.language ?? ""
    theme = book?.theme ?? ""
    sourceURL = book?.sourceURL ?? ""
    tags = Set(book?.tags.map(\.id) ?? [])
    datePurchased = book?.datePurchased.flatMap { DetailDateOnly.date($0) }
    dateReceived = book?.dateReceived.flatMap { DetailDateOnly.date($0) }
    dateStarted = book?.dateStarted.flatMap { DetailDateOnly.date($0) }
    dateCompleted = book?.dateCompleted.flatMap { DetailDateOnly.date($0) }
  }

  var sourceValidationMessage: String? {
    DiamondProjectDraft.normalizedSourceURL(sourceURL) == nil
      ? "Enter a valid http or https link, or leave it empty." : nil
  }

  var isValid: Bool {
    !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && totalPages >= 1
      && sourceValidationMessage == nil
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
      && notes == (record.notes ?? "")
      && isMystery == (record.isMystery ?? false)
      && isbn == (record.isbn ?? "")
      && bookFormat == (record.bookFormat ?? "")
      && edition == (record.edition ?? "")
      && publicationYear == record.publicationYear.flatMap { $0 == 0 ? nil : $0 }
      && language == (record.language ?? "")
      && theme == (record.theme ?? "")
      && sourceURL == (record.sourceURL ?? "")
      && datePurchased == record.datePurchased.flatMap { DetailDateOnly.date($0) }
      && dateReceived == record.dateReceived.flatMap { DetailDateOnly.date($0) }
      && dateStarted == record.dateStarted.flatMap { DetailDateOnly.date($0) }
      && dateCompleted == record.dateCompleted.flatMap { DetailDateOnly.date($0) }
  }
}

struct ColoringBookEditor: View {
  @Environment(\.protectedFiles) private var protectedFiles
  let library: LibrarySession
  var client: PocketBaseClient { library.client }
  var userID: String { library.userID }
  let book: ColoringBookRecord?
  let onLibraryRefresh: () async -> Void
  let onSaved: (ColoringBookRecord) -> Void

  private let baseline: ColoringBookDraft

  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @State private var draft: ColoringBookDraft
  @State private var isSaving = false
  @State private var errorMessage: String?

  @State private var coverChange: CoverChange = .unchanged
  @State private var triedTagIDs: Set<String> = []
  @State private var confirmedTagIDs: Set<String>
  @State private var savedBook: ColoringBookRecord?

  private var currentCoverURL: URL? {
    guard let book = savedBook ?? book, let cover = book.coverImage?.nonEmpty else { return nil }
    return protectedFiles?.url(
      collection: "coloring_books", recordID: book.id,
      filename: cover)
  }

  init(
    library: LibrarySession,
    book: ColoringBookRecord? = nil,
    onLibraryRefresh: @escaping () async -> Void = {},
    onSaved: @escaping (ColoringBookRecord) -> Void
  ) {
    self.library = library
    self.book = book
    self.onLibraryRefresh = onLibraryRefresh
    self.onSaved = onSaved
    let initialDraft = ColoringBookDraft(book: book)
    baseline = initialDraft
    _draft = State(initialValue: initialDraft)
    _confirmedTagIDs = State(initialValue: initialDraft.tags)
  }

  var body: some View {
    NavigationStack {
      Form {
        Group {
          CoverImageSection(
            currentCoverURL: currentCoverURL,
            placeholderSystemImage: "book.closed",
            accessibilityNoun: "Book cover", change: $coverChange)
            .disabled(isSaving)

          Section("Book") {
            TextField("Title", text: $draft.title)
            TextField("Series", text: $draft.series)

            Picker("Status", selection: $draft.status) {
              ForEach(BookStatus.allCases, id: \.self) { status in
                Text(status.label).tag(status.rawValue)
              }
            }

            LabeledContent("Total pages") {
              TextField("Total pages", value: $draft.totalPages, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
            }

            Toggle("Mystery book", isOn: $draft.isMystery)
          }
          .disabled(savedBook != nil || isSaving)

          Section("Credits") {
            ListPicker(
              library: library,
              userID: userID,
              kind: .publisher,
              initialName: book?.expand?.publisher?.name,
              selection: $draft.publisher
            )
            ListPicker(
              library: library,
              userID: userID,
              kind: .illustrator,
              initialName: book?.expand?.illustrator?.name,
              selection: $draft.illustrator
            )
            TagPicker(library: library, userID: userID, kind: .coloringTag, selection: $draft.tags)
          }
          .disabled(savedBook != nil || isSaving)

          Section {
            textRow("ISBN", text: $draft.isbn)
            Picker("Format", selection: $draft.bookFormat) {
              Text("Not set").tag("")
              Text("Paperback").tag("paperback")
              Text("Hardcover").tag("hardcover")
              Text("PDF").tag("pdf")
              Text("Printable pages").tag("printable_pages")
              Text("Magazine").tag("magazine")
              Text("Other").tag("other")
            }
            textRow("Edition", text: $draft.edition)
            LabeledContent("Year") {
              TextField("Not set", value: Binding(
                get: { draft.publicationYear },
                set: { draft.publicationYear = $0 == 0 ? nil : $0 }),
                format: .number.grouping(.never))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("Publication year")
            }
            Picker("Language", selection: $draft.language) {
              Text("Not set").tag("")
              Text("English").tag("english")
              Text("Spanish").tag("spanish")
              Text("French").tag("french")
              Text("German").tag("german")
              Text("Japanese").tag("japanese")
              Text("Other").tag("other")
              Text("Unknown").tag("unknown")
            }
            textRow("Theme", text: $draft.theme)
            TextField("Source link", text: $draft.sourceURL)
              .keyboardType(.URL)
              .autocorrectionDisabled()
              .textInputAutocapitalization(.never)
          } header: {
            Text("Bibliography")
          } footer: {
            if let message = draft.sourceValidationMessage {
              AccessibleErrorLabel(message: message)
            }
          }
          .disabled(savedBook != nil || isSaving)

          Section("Dates") {
            dateRow("Purchased", selection: $draft.datePurchased)
            dateRow("Received", selection: $draft.dateReceived)
            dateRow("Started", selection: $draft.dateStarted)
            dateRow("Completed", selection: $draft.dateCompleted)
          }
          .disabled(savedBook != nil || isSaving)

          Section("Notes") {
            TextField("Notes", text: $draft.notes, axis: .vertical)
              .lineLimit(3...8)
          }
          .disabled(savedBook != nil || isSaving)

          if book == nil || draft.totalPages != baseline.totalPages || coverChange != .unchanged || draft.tags != baseline.tags {
            Section { NeedsConnectionHint() }
          }

          if book != nil {
            Section {
              Text(
                "Changing the total updates the generated pages after save. Pages above the new total are removed only if you never touched them."
              )
              .font(.karla(.footnote))
              .foregroundStyle(theme.mutedForeground)
            }
          }

          if let errorMessage {
            Section {
              AccessibleErrorLabel(message: errorMessage)
                .accessibilityIdentifier("bookSaveError")
            }
          }
        }
        .listRowBackground(theme.card)
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
          .disabled(!draft.isValid || isSaving)
        }
      }
    }
  }

  private func textRow(_ label: String, text: Binding<String>) -> some View {
    LabeledContent(label) {
      TextField("Not set", text: text)
        .multilineTextAlignment(.trailing)
        .accessibilityLabel(label)
    }
  }

  @ViewBuilder
  private func dateRow(_ label: String, selection: Binding<Date?>) -> some View {
    if let date = selection.wrappedValue {
      HStack {
        DatePicker(label, selection: Binding(
          get: { selection.wrappedValue ?? date },
          set: { selection.wrappedValue = $0 }), displayedComponents: .date)
        Button("Clear \(label.lowercased()) date", systemImage: "xmark.circle.fill") {
          selection.wrappedValue = nil
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
      }
    } else {
      LabeledContent(label) {
        Button("Add") { selection.wrappedValue = Date() }
          .foregroundStyle(theme.primary)
          .accessibilityLabel("Add \(label.lowercased()) date")
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
      if let savedBook {
        saved = savedBook
      } else if let book {
        if draft.totalPages != baseline.totalPages {
          saved = try await library.updateOnline(
            collection: "coloring_books", id: book.id, body: write)
        } else {
          saved = try await library.update(
            collection: "coloring_books", id: book.id, body: write)
        }
      } else {
        saved = try await library.create(collection: "coloring_books", body: write)
      }
      savedBook = saved
      do {
        if draft.tags != confirmedTagIDs {
          let submittedTags = draft.tags
          let previousTags = baseline.tags.union(triedTagIDs)
          triedTagIDs.formUnion(submittedTags)
          try await TagLinks.sync(
            kind: .coloringTag, recordID: saved.id,
            from: previousTags, to: submittedTags, library: library)
          confirmedTagIDs = submittedTags
        }
      } catch APIError.cancelled {
        return
      } catch is CancellationError {
        return
      } catch {
        errorMessage = "The book was saved, but the tags could not be updated. Connect and try again."
        return
      }
      if coverChange != .unchanged {
        do {
          let covered: ColoringBookRecord = try await CoverUpload.apply(
            coverChange, collection: "coloring_books", recordID: saved.id,
            field: "cover_image", library: library)
          onSaved(covered)
        } catch APIError.cancelled {
          return
        } catch is CancellationError {
          return
        } catch {
          errorMessage = "The book was saved, but the cover could not be uploaded. Try again."
          return
        }
      } else {
        onSaved(saved)
      }
      dismiss()
    } catch APIError.cancelled {
      return
    } catch is CancellationError {
      return
    } catch {
      errorMessage = error.userMessage(
        permission: "Your account does not have permission to save this book.",
        offline: APIError.needsConnection(
          book == nil ? "Creating a book" : "Changing the page count"),
        fallback: "The book could not be saved. Try again."
      )
    }
  }
}

/// Page count alone. This must stay online because the server regenerates pages;
/// unlike other inline edits, it cannot be queued as a local record update.
struct ColoringBookPageCountEditor: View {
  let library: LibrarySession
  let book: ColoringBookRecord
  let onSaved: (ColoringBookRecord) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @State private var totalPages: Int?
  @State private var isSaving = false
  @State private var errorMessage: String?

  init(
    library: LibrarySession, book: ColoringBookRecord,
    onSaved: @escaping (ColoringBookRecord) -> Void
  ) {
    self.library = library
    self.book = book
    self.onSaved = onSaved
    _totalPages = State(initialValue: book.totalPages)
  }

  var body: some View {
    NavigationStack {
      Form {
        Group {
          Section {
            TextField("Total pages", value: $totalPages, format: .number)
              .keyboardType(.numberPad)
              .accessibilityIdentifier("pageCount.field")
          } header: {
            Text("Total pages")
          } footer: {
            Text(
              "Connect to change the total. Saving updates the generated pages. Pages above the new total are removed only if you never touched them."
            )
          }

          if let errorMessage {
            Section {
              AccessibleErrorLabel(message: errorMessage)
            }
          }
        }
        .listRowBackground(theme.card)
      }
      .themedScrollBackground()
      .navigationTitle("Page count")
      .navigationBarTitleDisplayMode(.inline)
      .interactiveDismissDisabled(isSaving)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          if isSaving {
            ProgressView()
          } else {
            Button("Save") {
              Task { await save() }
            }
            .disabled((totalPages ?? 0) < 1 || totalPages == book.totalPages)
            .accessibilityIdentifier("pageCount.save")
          }
        }
      }
    }
  }

  private func save() async {
    guard let totalPages, totalPages >= 1, !isSaving else { return }
    isSaving = true
    errorMessage = nil
    defer { isSaving = false }
    do {
      let saved: ColoringBookRecord = try await library.updateOnline(
        collection: "coloring_books", id: book.id, body: ["total_pages": totalPages])
      onSaved(saved)
      dismiss()
    } catch APIError.cancelled {
      return
    } catch APIError.offline {
      errorMessage = APIError.offlineMessage
    } catch {
      errorMessage = error.userMessage(
        permission: "Your account does not have permission to change this book.",
        fallback: "The page count could not be saved. Try again."
      )
    }
  }
}

extension FormDrawer {
  func presentPageCountEditor(
    book: ColoringBookRecord,
    library: LibrarySession,
    onSaved: @escaping (ColoringBookRecord) -> Void = { _ in }
  ) {
    present(detents: [.medium, .large]) {
      ColoringBookPageCountEditor(library: library, book: book, onSaved: onSaved)
    }
  }
}

// `user` is sent only on create; it is omitted on update so a save can never
// reassign ownership. Every other field is omitted on update when unchanged
// because the synthesized encoder drops nil keys, and a PATCH without a key
// leaves the server value untouched. When the user clears series, publisher,
// or illustrator, the key is included as `""`, PocketBase's unset value for a
// non-required text or relation field.
struct ColoringBookWrite: Encodable, Sendable {
  let user: String?
  let title: String?
  let series: String?
  let status: String?
  let totalPages: Int?
  let publisher: String?
  let illustrator: String?
  let notes: String?
  let isMystery: Bool?
  let isbn: String?
  let bookFormat: String?
  let edition: String?
  let publicationYear: Int?
  let language: String?
  let theme: String?
  let sourceURL: String?
  let datePurchased: String?
  let dateReceived: String?
  let dateStarted: String?
  let dateCompleted: String?

  enum CodingKeys: String, CodingKey {
    case user, title, series, status, publisher, illustrator
    case notes = "notes"
    case isMystery = "is_mystery"
    case isbn = "isbn"
    case bookFormat = "book_format"
    case edition = "edition"
    case publicationYear = "publication_year"
    case language = "language"
    case theme = "theme"
    case sourceURL = "source_url"
    case datePurchased = "date_purchased"
    case dateReceived = "date_received"
    case dateStarted = "date_started"
    case dateCompleted = "date_completed"
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
    let sourceURL = DiamondProjectDraft.normalizedSourceURL(draft.sourceURL) ?? draft.sourceURL
    if isCreate {
      return ColoringBookWrite(
        user: userID,
        title: trimmedTitle,
        series: trimmedSeries,
        status: draft.status,
        totalPages: draft.totalPages,
        publisher: draft.publisher,
        illustrator: draft.illustrator,
        notes: draft.notes,
        isMystery: draft.isMystery,
        isbn: draft.isbn,
        bookFormat: draft.bookFormat,
        edition: draft.edition,
        publicationYear: draft.publicationYear ?? 0,
        language: draft.language,
        theme: draft.theme,
        sourceURL: sourceURL,
        datePurchased: draft.datePurchased.map { DetailDateOnly.string(from: $0) } ?? "",
        dateReceived: draft.dateReceived.map { DetailDateOnly.string(from: $0) } ?? "",
        dateStarted: draft.dateStarted.map { DetailDateOnly.string(from: $0) } ?? "",
        dateCompleted: draft.dateCompleted.map { DetailDateOnly.string(from: $0) } ?? ""
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
      illustrator: draft.illustrator != baseline.illustrator ? draft.illustrator : nil,
      notes: draft.notes != baseline.notes ? draft.notes : nil,
      isMystery: draft.isMystery != baseline.isMystery ? draft.isMystery : nil,
      isbn: draft.isbn != baseline.isbn ? draft.isbn : nil,
      bookFormat: draft.bookFormat != baseline.bookFormat ? draft.bookFormat : nil,
      edition: draft.edition != baseline.edition ? draft.edition : nil,
      publicationYear: draft.publicationYear != baseline.publicationYear ? (draft.publicationYear ?? 0) : nil,
      language: draft.language != baseline.language ? draft.language : nil,
      theme: draft.theme != baseline.theme ? draft.theme : nil,
      sourceURL: sourceURL != DiamondProjectDraft.normalizedSourceURL(baseline.sourceURL)
        ? sourceURL : nil,
      datePurchased: draft.datePurchased != baseline.datePurchased ? (draft.datePurchased.map { DetailDateOnly.string(from: $0) } ?? "") : nil,
      dateReceived: draft.dateReceived != baseline.dateReceived ? (draft.dateReceived.map { DetailDateOnly.string(from: $0) } ?? "") : nil,
      dateStarted: draft.dateStarted != baseline.dateStarted ? (draft.dateStarted.map { DetailDateOnly.string(from: $0) } ?? "") : nil,
      dateCompleted: draft.dateCompleted != baseline.dateCompleted ? (draft.dateCompleted.map { DetailDateOnly.string(from: $0) } ?? "") : nil
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
  @Environment(\.protectedFiles) private var protectedFiles
  let library: LibrarySession
  let page: ColoringPageRecord
  let onLibraryRefresh: () async -> Void
  let onSaved: (ColoringPageRecord) -> Void

  private let baseline: ColoringPageDraft

  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @State private var draft: ColoringPageDraft
  @State private var isSaving = false
  @State private var errorMessage: String?

  init(
    library: LibrarySession,
    page: ColoringPageRecord,
    onLibraryRefresh: @escaping () async -> Void = {},
    onSaved: @escaping (ColoringPageRecord) -> Void
  ) {
    self.library = library
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
        Group {
          Section("Page \(page.pageNumber)") {
            if let photo = page.photos.first {
              RemoteArtwork(
                url: protectedFiles?.url(
                  collection: "coloring_pages",
                  recordID: page.id,
                  filename: photo,
                  thumb: ArtworkThumb.compact
                ),
                maxPixelDimension: 360
              ) { phase in
                if case .success(let image) = phase {
                  image.resizable().scaledToFill()
                } else {
                  RoundedRectangle(cornerRadius: Theme.Radius.medium)
                    .fill(theme.muted)
                    .overlay {
                      Image(systemName: LibrarySection.pages.systemImage)
                        .foregroundStyle(theme.mutedForeground)
                    }
                }
              }
              .frame(width: 120, height: 120)
              .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
              .accessibilityLabel("Page photo")
            }

            LabeledContent("Book", value: page.expand?.book?.title ?? "Unknown book")
          }

          Section {
            Picker("Status", selection: $draft.status) {
              ForEach(PageStatus.allCases, id: \.self) { status in
                Text(status.label).tag(status.rawValue)
              }
            }

            TextField("Revealed subject", text: $draft.revealedSubject)

            Text("Changing status sets these dates. You can also change them on the page.")
              .font(.karla(.footnote))
              .foregroundStyle(theme.mutedForeground)
          }

          if let errorMessage {
            Section {
              AccessibleErrorLabel(message: errorMessage)
                .accessibilityIdentifier("pageSaveError")
            }
          }
        }
        .listRowBackground(theme.card)
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
          .disabled(isSaving)
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
      let saved: ColoringPageRecord = try await library.update(
        collection: "coloring_pages",
        id: page.id,
        body: write
      )
      onSaved(saved)
      dismiss()
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
struct ColoringPageWrite: Encodable, Sendable {
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
