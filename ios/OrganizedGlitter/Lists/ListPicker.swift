import SwiftUI

/// Form row that picks a user-scoped list entry.
/// `selection` is the record id; "" means none (PocketBase relation-clear sentinel).
/// Must be hosted inside a NavigationStack.
struct ListPicker: View {
  let library: LibrarySession
  let userID: String
  let kind: ListKind
  let initialName: String?
  @Binding var selection: String

  // Options live here (not in the pushed list) so the row can show the picked
  // name after the list pops, including a record created moments ago.
  @State private var options: [NamedRelationRecord]?

  var body: some View {
    NavigationLink {
      ListOptionList(
        library: library,
        userID: userID,
        kind: kind,
        selection: Binding(
          get: { selection.isEmpty ? [] : [selection] },
          set: { selection = $0.first ?? "" }
        ),
        multiple: false,
        options: $options
      )
    } label: {
      LabeledContent(kind.singular, value: displayName)
    }
    .accessibilityIdentifier("\(kind.singular.lowercased())Picker")
  }

  private var displayName: String {
    if let name = options?.first(where: { $0.id == selection })?.name {
      name
    } else if !selection.isEmpty, let initialName {
      initialName
    } else {
      "None"
    }
  }
}

struct TagPicker: View {
  let library: LibrarySession
  let userID: String
  let kind: ListKind
  @Binding var selection: Set<String>
  @State private var options: [NamedRelationRecord]?

  init(
    library: LibrarySession, userID: String, kind: ListKind,
    selection: Binding<Set<String>>
  ) {
    precondition(kind.isTag)
    self.library = library
    self.userID = userID
    self.kind = kind
    self._selection = selection
  }

  var body: some View {
    NavigationLink {
      ListOptionList(
        library: library, userID: userID, kind: kind,
        selection: $selection, multiple: true, options: $options)
    } label: {
      LabeledContent("Tags", value: Self.summary(
        selection: selection,
        options: options ?? TaxonomyOptions.fromDownloadedLibrary(
          library.items, kind: kind, userID: userID)))
    }
    .accessibilityIdentifier("tagPicker")
  }

  static func summary(selection: Set<String>, options: [NamedRelationRecord]) -> String {
    guard !selection.isEmpty else { return "None" }
    let names = options.filter { selection.contains($0.id) }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
      .map(\.name)
    guard selection.count <= 3, names.count == selection.count else {
      return "\(selection.count) tags"
    }
    return names.formatted(.list(type: .and))
  }
}

private struct ListOptionList: View {
  let library: LibrarySession
  let userID: String
  let kind: ListKind
  @Binding var selection: Set<String>
  let multiple: Bool
  @Binding var options: [NamedRelationRecord]?

  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @State private var errorMessage: String?
  @State private var isCreating = false
  @State private var newName = ""
  @State private var usingDownloadedOptions = false

  var body: some View {
    List {
      Group {
        if let options {
          Section {
            if !multiple { selectionRow(id: "", name: "None") }
            ForEach(options, id: \.id) { option in
              selectionRow(id: option.id, name: option.name)
            }
          }

          Section {
            if usingDownloadedOptions {
              Text("Showing \(kind.singular.lowercased()) options used by your downloaded library. Try again when the service is available for the full list.")
                .font(.karla(.footnote))
            }
            if let errorMessage {
              AccessibleErrorLabel(message: errorMessage)
              Button("Try Again") {
                Task { await load() }
              }
            }
            HStack {
              TextField("New \(kind.singular.lowercased())", text: $newName)
                .submitLabel(.done)
                .onSubmit { Task { await create() } }
                .disabled(isCreating)
                .accessibilityIdentifier("taxonomy.newName")
              if isCreating {
                ProgressView()
              } else {
                Button("Add") {
                  Task { await create() }
                }
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(theme.primary)
                .disabled(trimmedNewName.isEmpty)
                .accessibilityLabel("Add \(kind.singular.lowercased())")
                .accessibilityIdentifier("taxonomy.add")
              }
            }
          } footer: {
            NeedsConnectionHint()
          }
        } else if let errorMessage {
          Section {
            AccessibleErrorLabel(message: errorMessage)
            Button("Try Again") {
              Task { await load() }
            }
          }
        } else {
          Section {
            ProgressView()
              .frame(maxWidth: .infinity)
          }
        }
      }
      .listRowBackground(theme.card)
    }
    .themedScrollBackground()
    .navigationTitle(multiple ? kind.title : kind.singular)
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await load()
    }
  }

  private var trimmedNewName: String {
    newName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func selectionRow(id: String, name: String) -> some View {
    Button {
      if multiple {
        if selection.contains(id) { selection.remove(id) }
        else { selection.insert(id) }
      } else {
        selection = id.isEmpty ? [] : [id]
        dismiss()
      }
    } label: {
      HStack {
        Text(name)
          .foregroundStyle(theme.cardForeground)
        Spacer()
        if (id.isEmpty ? selection.isEmpty : selection.contains(id)) {
          Image(systemName: "checkmark")
            .foregroundStyle(theme.primary)
            .accessibilityHidden(true)
        }
      }
    }
    .frame(minHeight: 44)
    .accessibilityLabel(name)
    .accessibilityAddTraits((id.isEmpty ? selection.isEmpty : selection.contains(id)) ? .isSelected : [])
  }

  private func load() async {
    errorMessage = nil
    if options == nil {
      options = TaxonomyOptions.fromDownloadedLibrary(
        library.items, kind: kind, userID: userID)
    }
    do {
      let records: [NamedRelationRecord] = try await library.client.allRecords(
        collection: kind.collection,
        filter: PocketBaseFilter.equals(.user, userID),
        sort: "+name"
      )
      options = records
      usingDownloadedOptions = false
    } catch APIError.cancelled {
      return
    } catch APIError.offline {
      usingDownloadedOptions = true
      errorMessage = "Reconnect to see all \(kind.singular.lowercased()) options."
    } catch {
      usingDownloadedOptions = true
      errorMessage = message(
        error,
        permission: "Your account does not have permission to view \(kind.singular.lowercased()) options.",
        offline: APIError.offlineMessage,
        fallback: "\(kind.singular) options are unavailable right now. Try again."
      )
    }
  }

  private func create() async {
    let name = trimmedNewName
    guard !name.isEmpty, !isCreating else {
      return
    }

    isCreating = true
    errorMessage = nil
    defer { isCreating = false }

    do {
      let created: NamedRelationRecord = try await library.create(
        collection: kind.collection,
        body: kind.createBody(name: name, userID: userID)
      )
      var updated = options ?? []
      let index =
        updated.firstIndex {
          created.name.localizedCaseInsensitiveCompare($0.name) == .orderedAscending
        } ?? updated.endIndex
      updated.insert(created, at: index)
      options = updated
      newName = ""
      if multiple { selection.insert(created.id) }
      else {
        selection = [created.id]
        dismiss()
      }
    } catch APIError.cancelled {
      return
    } catch {
      errorMessage = message(
        error,
        permission: "Your account does not have permission to add a \(kind.singular.lowercased()).",
        offline: APIError.needsConnection("Adding a \(kind.singular.lowercased())"),
        fallback: "The \(kind.singular.lowercased()) could not be created. Try again."
      )
    }
  }

  private func message(
    _ error: Error, permission: String, offline: String, fallback: String
  ) -> String {
    error.userMessage(permission: permission, offline: offline, fallback: fallback)
  }
}

enum TaxonomyOptions {
  static func fromDownloadedLibrary(
    _ items: [LibraryItem], kind: ListKind, userID: String
  ) -> [NamedRelationRecord] {
    var recordsByID: [String: NamedRelationRecord] = [:]
    let bookOwners = Dictionary(
      items.compactMap { item -> (String, String)? in
        guard case .book(let book) = item else { return nil }
        return (book.id, book.user)
      }, uniquingKeysWith: { first, _ in first })
    for item in items {
      let records: [NamedRelationRecord]
      switch item {
      case .diamond(let project) where project.user == userID:
        switch kind {
        case .company: records = [project.expand?.company].compactMap { $0 }
        case .artist: records = [project.expand?.artist].compactMap { $0 }
        case .diamondTag: records = project.tags.map { NamedRelationRecord(id: $0.id, name: $0.name) }
        default: records = []
        }
      case .book(let book) where book.user == userID:
        switch kind {
        case .publisher: records = [book.expand?.publisher].compactMap { $0 }
        case .illustrator: records = [book.expand?.illustrator].compactMap { $0 }
        case .coloringTag: records = book.tags.map { NamedRelationRecord(id: $0.id, name: $0.name) }
        default: records = []
        }
      case .page(let page)
      where (bookOwners[page.book] ?? page.expand?.book?.user) == userID && kind == .medium:
        records = page.expand?.mediums ?? []
      default: records = []
      }
      for record in records { recordsByID[record.id] = record }
    }
    return recordsByID.values.sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }
}
