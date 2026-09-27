import SwiftUI
import UIKit

struct LibrarySyncStatusView: View {
  @Environment(FormDrawer.self) private var formDrawer
  let library: LibrarySession

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
            formDrawer.present(detents: [.medium, .large]) {
              NavigationStack { LibraryConflictView(library: library) }
            }
          }
        }
        .disabled(library.isSyncing || formDrawer.isPresenting)
      }
      .padding()
      .background(.regularMaterial)
      .accessibilityIdentifier("library.syncStatus")
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
          }
        }
      }
    }
    .navigationTitle("Review Saved Changes")
    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    .onChange(of: errorMessage) { _, message in
      guard let message, UIAccessibility.isVoiceOverRunning else { return }
      UIAccessibility.post(notification: .announcement, argument: message)
    }
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
  @State private var changes: [LocalConflictChange]?
  @State private var errorMessage: String?
  @State private var isResolving = false

  var body: some View {
    Group {
      if let changes {
        if let errorMessage { AccessibleErrorLabel(message: errorMessage) }
        if changes.isEmpty {
          Text("The compared fields currently match.")
        }
        ForEach(changes, id: \.field) { change in
          VStack(alignment: .leading, spacing: 4) {
            Text(change.field.replacingOccurrences(of: "_", with: " ").capitalized)
              .font(.headline)
            Text("\(change.isComparisonOnly ? "When you saved" : "On this device"): \(display(change.local))")
            Text("In your account: \(display(change.server))")
            if change.isComparisonOnly {
              Text("This field was included in the conflict check.")
                .font(.footnote)
            }
          }
        }
        Button("Keep My Changes") { resolve(retainLocal: true) }
          .disabled(isResolving)
        Button("Use Account Version", role: .destructive) { resolve(retainLocal: false) }
          .disabled(isResolving)
      } else if let errorMessage {
        AccessibleErrorLabel(message: errorMessage)
        Button("Try Again") { Task { await load() } }
      } else {
        ProgressView("Loading differences")
      }
    }
    .task(id: entry.item) { await load() }
    .onChange(of: errorMessage) { _, message in
      guard let message, UIAccessibility.isVoiceOverRunning else { return }
      UIAccessibility.post(notification: .announcement, argument: message)
    }
  }

  private func load() async {
    changes = nil
    errorMessage = nil
    do {
      changes = try await library.store.conflictChanges(
        scope: library.scope, key: entry.item.localRecordKey)
    } catch {
      errorMessage = "The differences could not be loaded. Try again."
    }
  }

  private func resolve(retainLocal: Bool) {
    guard changes != nil, !isResolving else { return }
    isResolving = true
    Task {
      defer { isResolving = false }
      do { try await library.resolve(entry, retainLocal: retainLocal) }
      catch { errorMessage = "The changes could not be resolved. Please try again." }
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
