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
          .font(.karla(.footnote))
          .frame(maxWidth: .infinity, alignment: .leading)
        Button(actionTitle) {
          if library.conflicts.isEmpty {
            Task { try? await library.refresh(force: true) }
          } else {
            formDrawer.present(detents: [.medium, .large]) {
              NavigationStack { LibraryConflictView(library: library) }
            }
          }
        }
        .disabledWhileFormPresented(formDrawer, or: library.isSyncing)
      }
      .padding()
      .background(.regularMaterial)
      .accessibilityIdentifier("library.syncStatus")
    }
  }

  private var message: String {
    if !library.conflicts.isEmpty {
      return "\(library.conflicts.count) saved item\(library.conflicts.count == 1 ? "" : "s") need review. Your edits are still on this device."
    }
    if library.isSyncing { return "Synchronizing your saved changes…" }
    if library.pendingCount > 0 {
      let count = library.pendingCount
      return "\(count) item\(count == 1 ? "" : "s") saved on this device and waiting to sync."
        + (library.syncMessage.map { " \($0)" } ?? "")
    }
    if let message = library.syncMessage { return message }
    return "Synchronizing your library…"
  }

  private var actionTitle: String {
    if !library.conflicts.isEmpty { return "Review" }
    return library.syncMessage == nil ? "Sync" : "Try Again"
  }
}

private struct LibraryConflictView: View {
  let library: LibrarySession
  @Environment(\.dismiss) private var dismiss
  @State private var errorMessage: String?
  @State private var discardEntry: LocalLibraryEntry?

  var body: some View {
    List {
      if let errorMessage { AccessibleErrorLabel(message: errorMessage) }
      ForEach(library.conflicts, id: \.item.id) { entry in
        Section(entry.item.title) {
          if entry.conflict == .deletedOnServer || entry.conflict == .rejectedByServer {
            Text(entry.conflict == .deletedOnServer
              ? "This item was removed from your account. Your unsent version is still on this device."
              : "Your account could not accept these changes. Export them before discarding and editing again.")
            ShareLink("Export Unsent Details", item: exportText(entry.item))
            Button("Discard Unsent Changes", role: .destructive) {
              discardEntry = entry
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
    .confirmationDialog(
      "Discard unsent changes?",
      isPresented: Binding(
        get: { discardEntry != nil },
        set: { if !$0 { discardEntry = nil } }
      ),
      presenting: discardEntry
    ) { entry in
      Button("Discard Changes", role: .destructive) {
        resolve(entry, retainLocal: false)
        discardEntry = nil
      }
    } message: { entry in
      Text("Your changes to \(entry.item.title) exist only on this device. Discarding cannot be undone.")
    }
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
  @State private var showingDiscardConfirmation = false

  var body: some View {
    Group {
      if let changes {
        let display = ConflictValueDisplay(
          item: entry.item, accountItems: library.items, userID: library.userID)
        if let errorMessage { AccessibleErrorLabel(message: errorMessage) }
        if changes.isEmpty {
          Text("The compared fields currently match.")
        }
        ForEach(changes, id: \.field) { change in
          VStack(alignment: .leading, spacing: 4) {
            Text(ConflictFieldName.label(for: change.field))
              .font(.karla(.headline))
            Text("\(change.isComparisonOnly ? "When you saved" : "On this device"): \(display.text(change.local, field: change.field))")
            Text("In your account: \(display.text(change.server, field: change.field))")
            if change.isComparisonOnly {
              Text("This field was included in the conflict check.")
                .font(.karla(.footnote))
            }
          }
        }
        Button("Keep My Changes") { resolve(retainLocal: true) }
          .disabled(isResolving)
        Button("Use Account Version", role: .destructive) {
          showingDiscardConfirmation = true
        }
          .disabled(isResolving)
      } else if let errorMessage {
        AccessibleErrorLabel(message: errorMessage)
        Button("Try Again") { Task { await load() } }
      } else {
        ProgressView("Loading differences")
      }
    }
    .task(id: entry.item) { await load() }
    .confirmationDialog(
      "Use the account version?",
      isPresented: $showingDiscardConfirmation
    ) {
      Button("Discard My Changes", role: .destructive) {
        resolve(retainLocal: false)
      }
    } message: {
      Text("Your unsent changes to \(entry.item.title) will be discarded. This cannot be undone.")
    }
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
}

struct ConflictValueDisplay {
  let item: LibraryItem
  private let relationNames: [String: [String: String]]

  init(item: LibraryItem, accountItems: [LibraryItem], userID: String) {
    self.item = item
    var names: [String: [String: String]] = [:]
    for candidate in [item] + accountItems {
      switch candidate {
      case .diamond(let project) where project.user == userID:
        if let record = project.expand?.company, let name = record.name.nonEmpty {
          names["company", default: [:]][record.id] = name
        }
        if let record = project.expand?.artist, let name = record.name.nonEmpty {
          names["artist", default: [:]][record.id] = name
        }
      case .book(let book) where book.user == userID:
        if let record = book.expand?.publisher, let name = record.name.nonEmpty {
          names["publisher", default: [:]][record.id] = name
        }
        if let record = book.expand?.illustrator, let name = record.name.nonEmpty {
          names["illustrator", default: [:]][record.id] = name
        }
      default:
        break
      }
    }
    relationNames = names
  }

  func text(_ value: LocalJSONValue, field: String) -> String {
    switch value {
    case .string(let value):
      if value.isEmpty { return "Not set" }
      if ["company", "artist", "publisher", "illustrator"].contains(field) {
        return relationNames[field]?[value] ?? "\(ConflictFieldName.label(for: field)) unavailable"
      }
      if field == "status" {
        switch item {
        case .diamond: return DiamondStatus(rawValue: value)?.label ?? value
        case .book: return BookStatus(rawValue: value)?.label ?? value
        case .page: return PageStatus(rawValue: value)?.label ?? value
        }
      }
      return value
    case .number(let value): return value.formatted()
    case .bool(let value): return value ? "Yes" : "No"
    case .null: return "Not set"
    }
  }
}

enum ConflictFieldName {
  static func label(for field: String) -> String {
    return switch field {
    case "kit_category": "Kit type"
    case "drill_shape": "Drill shape"
    case "source_url": "Source link"
    case "general_notes": "Notes"
    case "date_purchased": "Purchased date"
    case "date_received": "Received date"
    case "date_started", "started_at": "Started date"
    case "date_completed", "completed_at": "Completed date"
    case "total_diamonds": "Total diamonds"
    case "color_count": "Color count"
    case "revealed_subject": "Revealed subject"
    case "revealed_at": "Revealed date"
    default: field.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }
}
