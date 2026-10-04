import SwiftUI

struct ManageListsView: View {
  @Environment(\.theme) private var theme

  let library: LibrarySession
  let userID: String
  let verticals: VerticalPreferences

  var body: some View {
    List {
      if verticals.diamondPainting {
        Section("Diamond art") { rows(ListKind.diamond) }
      }
      if verticals.coloringBooks {
        Section("Coloring") { rows(ListKind.coloring) }
      }
    }
    .font(.karla(.body))
    .themedScrollBackground()
    .navigationTitle("Manage lists")
  }

  private func rows(_ kinds: [ListKind]) -> some View {
    ForEach(kinds) { kind in
      NavigationLink {
        ListEntriesView(library: library, userID: userID, kind: kind)
      } label: {
        Label(kind.title, systemImage: kind.systemImage)
      }
      .listRowBackground(theme.card)
    }
  }
}

struct ListEntriesView: View {
  @Environment(\.theme) private var theme
  @Environment(\.connectionAvailable) private var connectionAvailable

  let library: LibrarySession
  let userID: String
  let kind: ListKind

  @State private var entries: [NamedRelationRecord]?
  @State private var errorMessage: String?
  @State private var busy = false
  @State private var showNameAlert = false
  @State private var editing: NamedRelationRecord?
  @State private var name = ""
  @State private var deletion: NamedRelationRecord?
  @State private var showDeleteConfirmation = false
  @State private var usage: ListUsagePresentation?

  private var canWrite: Bool { connectionAvailable && !busy && entries != nil }

  var body: some View {
    List {
      Section {
        if let entries {
          if entries.isEmpty {
            ContentUnavailableView(
              "No \(kind.title.lowercased())", systemImage: kind.systemImage,
              description: Text("Add one here or while editing a record."))
          }
          ForEach(entries, id: \.id) { entry in
            Text(entry.name)
              .foregroundStyle(theme.cardForeground)
              .swipeActions(allowsFullSwipe: false) { actions(entry) }
              .contextMenu { actions(entry) }
          }
        } else if errorMessage == nil {
          ProgressView("Loading lists")
        }
      } footer: {
        NeedsConnectionHint()
      }
      .listRowBackground(theme.card)

      if let errorMessage {
        Section {
          AccessibleErrorLabel(message: errorMessage)
          if entries == nil {
            Button("Try Again") { Task { await load() } }
              .accessibilityLabel("Try loading \(kind.title.lowercased()) again")
              .disabled(busy)
          }
        }
        .listRowBackground(theme.card)
      }
    }
    .font(.karla(.body))
    .themedScrollBackground()
    .navigationTitle(kind.title)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Add \(kind.singular.lowercased())", systemImage: "plus") {
          editing = nil
          name = ""
          showNameAlert = true
        }
        .disabled(!canWrite)
      }
    }
    .task { await load() }
    .refreshable { await load() }
    .alert(editing == nil ? "Add \(kind.singular.lowercased())" : "Rename \(kind.singular.lowercased())",
           isPresented: $showNameAlert) {
      TextField("Name", text: $name)
        .accessibilityLabel("\(kind.singular) name")
      Button("Cancel", role: .cancel) {}
      Button("Save") { Task { await save() } }
        .disabled(!canWrite || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || kind.nameValidationMessage(name) != nil)
    } message: {
      if let validation = kind.nameValidationMessage(name) {
        Text(validation)
      }
    }
    .confirmationDialog(
      "Delete “\(deletion?.name ?? "")”?", isPresented: $showDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        if let deletion { Task { await delete(deletion) } }
      }
      .disabled(!canWrite)
      Button("Cancel", role: .cancel) {}
    }
    .sheet(item: $usage) { presentation in
      NavigationStack {
        List {
          Section {
            Text("Remove it from these first, then delete it.")
            ForEach(Array(presentation.titles.enumerated()), id: \.offset) { _, title in
              Text(title)
            }
            if presentation.total > presentation.titles.count {
              Text("and \(presentation.total - presentation.titles.count) more")
            }
          }
          .listRowBackground(theme.card)
        }
        .font(.karla(.body))
        .themedScrollBackground()
        .navigationTitle("“\(presentation.name)” is in use")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { usage = nil }
              .accessibilityLabel("Done viewing list usage")
          }
        }
      }
    }
  }

  private func actions(_ entry: NamedRelationRecord) -> some View {
    Group {
      Button("Rename", systemImage: "pencil") {
        editing = entry
        name = entry.name
        showNameAlert = true
      }
      .accessibilityLabel("Rename \(entry.name)")
      Button("Delete", systemImage: "trash", role: .destructive) {
        Task { await checkUsage(entry) }
      }
      .accessibilityLabel("Delete \(entry.name)")
    }
    .disabled(!canWrite)
  }

  private func load() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    errorMessage = nil
    do {
      entries = try await library.client.allRecords(
        collection: kind.collection,
        filter: PocketBaseFilter.equals(.user, userID), sort: "+name")
    } catch APIError.cancelled {
    } catch {
      errorMessage = message(error, action: "Loading")
    }
  }

  private func save() async {
    guard canWrite else { return }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if let validation = kind.nameValidationMessage(trimmed) ?? ListEntryNames.validation(
      trimmed, entries: entries ?? [], excluding: editing?.id
    ) {
      errorMessage = validation
      return
    }
    busy = true
    defer { busy = false }
    errorMessage = nil
    do {
      let saved: NamedRelationRecord
      if let editing {
        saved = try await library.updateOnline(
          collection: kind.collection, id: editing.id, body: kind.renameBody(name: trimmed))
      } else {
        saved = try await library.create(
          collection: kind.collection, body: kind.createBody(name: trimmed, userID: userID))
      }
      var updated = (entries ?? []).filter { $0.id != saved.id }
      updated.append(saved)
      entries = updated.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    } catch APIError.cancelled {
    } catch {
      errorMessage = message(error, action: "Saving")
    }
  }

  private func checkUsage(_ entry: NamedRelationRecord) async {
    guard canWrite else { return }
    busy = true
    defer { busy = false }
    errorMessage = nil
    do {
      let result = try await fetchUsage(entry)
      if result.total > 0 {
        usage = result
      } else {
        deletion = entry
        showDeleteConfirmation = true
      }
    } catch APIError.cancelled {
    } catch {
      errorMessage = message(error, action: "Checking usage of")
    }
  }

  private var usageExpansion: String? {
    switch kind {
    case .diamondTag: "project"
    case .coloringTag, .medium: "book"
    default: nil
    }
  }

  private func fetchUsage(_ entry: NamedRelationRecord) async throws -> ListUsagePresentation {
    let result: RecordList<ListUsageRecord> = try await library.client.list(
      collection: kind.usageCollection, perPage: 20,
      filter: kind.usageFilter(entryID: entry.id), sort: "+id",
      expand: usageExpansion)
    return ListUsagePresentation(
      name: entry.name, titles: result.items.map { $0.displayTitle(kind: kind) },
      total: result.totalItems)
  }

  private func delete(_ entry: NamedRelationRecord) async {
    guard canWrite else { return }
    busy = true
    defer { busy = false }
    errorMessage = nil
    do {
      try await library.delete(collection: kind.collection, id: entry.id)
      entries?.removeAll { $0.id == entry.id }
    } catch APIError.cancelled {
    } catch APIError.validation(let detail) where detail.localizedCaseInsensitiveContains("still in use") {
      usage = ListUsagePresentation(name: entry.name, titles: [], total: 0)
      if let refreshed = try? await fetchUsage(entry) { usage = refreshed }
    } catch {
      errorMessage = message(error, action: "Deleting")
    }
  }

  private func message(_ error: Error, action: String) -> String {
    error.userMessage(
      permission: "Your account does not have permission to manage this list.",
      offline: APIError.needsConnection("\(action) a \(kind.singular.lowercased())"),
      fallback: "The list could not be updated. Try again.")
  }
}

enum ListEntryNames {
  static func validation(
    _ name: String, entries: [NamedRelationRecord], excluding id: String? = nil
  ) -> String? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "Enter a name." }
    if entries.contains(where: {
      $0.id != id && $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
        .localizedCaseInsensitiveCompare(trimmed) == .orderedSame
    }) {
      return "An entry with that name already exists in this list."
    }
    return nil
  }
}

struct ListUsageRecord: Decodable, Sendable {
  let title: String?
  let pageNumber: Int?
  let expand: Expansion?

  struct Parent: Decodable, Sendable {
    let title: String
  }

  struct Expansion: Decodable, Sendable {
    let project: Parent?
    let book: Parent?
  }

  enum CodingKeys: String, CodingKey {
    case title, expand
    case pageNumber = "page_number"
  }

  func displayTitle(kind: ListKind) -> String {
    switch kind {
    case .diamondTag: expand?.project?.title ?? "Unavailable project"
    case .coloringTag: expand?.book?.title ?? "Unavailable book"
    case .medium: "Page \(pageNumber.map(String.init) ?? "?") · \(expand?.book?.title ?? "Unavailable book")"
    default: title ?? "Untitled record"
    }
  }
}

private struct ListUsagePresentation: Identifiable {
  let id = UUID()
  let name: String
  let titles: [String]
  let total: Int
}
