import SwiftUI

struct LibrarySyncStatusView: View {
  let library: LibrarySession
  @State private var showingChanges = false

  var body: some View {
    if library.isSyncing || library.pendingCount > 0 || library.syncMessage != nil {
      HStack(spacing: 12) {
        if library.isSyncing { ProgressView().accessibilityLabel("Synchronizing library") }
        Text(message)
          .font(.footnote)
          .frame(maxWidth: .infinity, alignment: .leading)
        Button(library.conflicts.isEmpty ? "Sync" : "Review") {
          if library.conflicts.isEmpty {
            Task { try? await library.refresh(force: true) }
          } else {
            showingChanges = true
          }
        }
        .disabled(library.isSyncing)
      }
      .padding()
      .background(.regularMaterial)
      .sheet(isPresented: $showingChanges) {
        NavigationStack { LibraryConflictView(library: library) }
      }
    }
  }

  private var message: String {
    if !library.conflicts.isEmpty { return "Some saved changes need your attention." }
    if library.pendingCount > 0 { return "Saved on this device. Waiting to sync." }
    if let message = library.syncMessage { return message }
    return "Synchronizing your library…"
  }
}

private struct LibraryConflictView: View {
  let library: LibrarySession
  @Environment(\.dismiss) private var dismiss
  @State private var errorMessage: String?

  var body: some View {
    List {
      if let errorMessage { Text(errorMessage) }
      ForEach(library.conflicts, id: \.item.id) { entry in
        Section(entry.item.title) {
          if entry.conflict == .deletedOnServer || entry.conflict == .rejectedByServer {
            Text(entry.conflict == .deletedOnServer
              ? "This item was removed from your account. Your unsent version is still on this device."
              : "Your account could not accept these changes. Export them before discarding and editing again.")
            ShareLink("Export Unsent Details", item: exportText(entry.item))
            Button("Discard Unsent Changes", role: .destructive) {
              resolve(entry, retainLocal: false)
            }
          } else {
            Text("This item changed on another device. Review both versions before choosing which changes to keep.")
            LibraryConflictFields(library: library, entry: entry)
            Button("Keep My Changes") { resolve(entry, retainLocal: true) }
            Button("Use Account Version", role: .destructive) { resolve(entry, retainLocal: false) }
          }
        }
      }
    }
    .navigationTitle("Review Saved Changes")
    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
  }

  private func resolve(_ entry: LocalLibraryEntry, retainLocal: Bool) {
    Task {
      do { try await library.resolve(entry, retainLocal: retainLocal) }
      catch { errorMessage = "The changes could not be resolved. Please try again." }
    }
  }

  private func exportText(_ item: LibraryItem) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data: Data?
    switch item {
    case .diamond(let record): data = try? encoder.encode(record)
    case .book(let record): data = try? encoder.encode(record)
    case .page(let record): data = try? encoder.encode(record)
    }
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? item.title
  }
}

private struct LibraryConflictFields: View {
  let library: LibrarySession
  let entry: LocalLibraryEntry
  @State private var changes: [LocalConflictChange] = []

  var body: some View {
    ForEach(changes, id: \.field) { change in
      VStack(alignment: .leading, spacing: 4) {
        Text(change.field.replacingOccurrences(of: "_", with: " ").capitalized).font(.headline)
        Text("On this device: \(display(change.local))")
        Text("In your account: \(display(change.server))")
      }
    }
    .task {
      changes = (try? await library.store.conflictChanges(
        scope: library.scope, key: entry.item.localRecordKey)) ?? []
    }
  }

  private func display(_ value: LocalJSONValue) -> String {
    switch value {
    case .string(let value): value.isEmpty ? "Not set" : value
    case .number(let value): value.formatted()
    case .bool(let value): value ? "Yes" : "No"
    case .null: "Not set"
    }
  }
}
