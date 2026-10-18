import SwiftUI

struct PageMediumEditor: View {
  let page: ColoringPageRecord
  let model: LibraryItemDetailModel
  let onCollectionChanged: @MainActor @Sendable () async -> Void
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @Environment(\.connectionAvailable) private var connectionAvailable
  @State private var selection: Set<String> = []
  @State private var baseline: [String]?
  @State private var options: [NamedRelationRecord] = []
  @State private var loading = true
  @State private var busy = false
  @State private var errorMessage: String?
  @State private var newName = ""

  private var library: LibrarySession { model.library }
  private var attempt: PageMediumAttempt? { library.mediumAttempts.first { $0.pageID == page.id } }
  private var canEdit: Bool { !busy && !loading && attempt == nil && connectionAvailable }

  var body: some View {
    NavigationStack {
      List {
        if let attempt {
          Section("Review medium save") {
            PageMediumRecovery(library: library, attempt: attempt) {
              await model.load()
              await onCollectionChanged()
              if library.mediumAttempts.allSatisfy({ $0.pageID != page.id }) { dismiss() }
            }
          }
        }
        Section {
          ListMultiSelectRows(options: options, selection: $selection, isDisabled: !canEdit, selectionLimit: 99)
          if !selection.isEmpty {
            Button("Clear selection") { selection.removeAll() }
              .disabled(!canEdit)
              .accessibilityIdentifier("mediums.clear")
          }
          if options.isEmpty && !loading {
            Text("No mediums yet. Add one below, then select it for this page.")
          }
          let unavailable = selection.subtracting(options.map(\.id)).count
          if unavailable > 0 {
            Text("\(unavailable) unavailable medium\(unavailable == 1 ? "" : "s") remain selected.")
              .font(.karla(.footnote))
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Section {
          TextField("New medium", text: $newName)
            .disabled(!canEdit)
            .accessibilityIdentifier("mediums.newName")
          Button("Add medium") { Task { await create() } }
            .disabled(!canEdit || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
          Text("Add a medium")
        } footer: {
          NeedsConnectionHint()
        }
        if loading || busy { ProgressView(loading ? "Loading mediums…" : "Saving mediums…") }
        if let errorMessage {
          Section {
            AccessibleErrorLabel(message: errorMessage)
            if !busy && attempt == nil {
              Button("Try again") { Task { await load() } }
                .disabled(!connectionAvailable)
            }
          }
        }
      }
      .listRowBackground(theme.card)
      .themedScrollBackground()
      .navigationTitle("Mediums")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(attempt == nil ? "Cancel" : "Close") { dismiss() }.disabled(busy)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { Task { await save() } }
            .disabled(!canEdit || baseline == nil || selection == Set(baseline ?? []) || selection.count > 99)
            .accessibilityIdentifier("mediums.done")
        }
      }
      .interactiveDismissDisabled(busy)
      .task { await load() }
    }
    .presentationSizing(.form)
  }

  private func load() async {
    loading = true
    errorMessage = nil
    defer { loading = false }
    do {
      try await library.loadLocal()
      options = ListOptions.fromDownloadedLibrary(library.items, kind: .medium, userID: library.userID)
      if let attempt {
        baseline = attempt.base.mediums
        selection = Set(attempt.patch.mediums)
      } else if baseline == nil {
        var current: ColoringPageRecord = try library.record(collection: "coloring_pages", id: page.id)
        if current.mediumIDs == nil {
          try await library.refreshFromServer()
          current = try library.record(collection: "coloring_pages", id: page.id)
        }
        guard let raw = current.mediumIDs else { throw APIError.decoding }
        baseline = raw
        selection = Set(raw)
      }
      options = try await library.mediumOptions()
    } catch {
      errorMessage = error.userMessage(
        permission: "Your account cannot view these mediums.",
        offline: baseline == nil ? "Mediums could not be loaded. Try again."
          : "Showing downloaded mediums. Reconnect to see the full list and save.",
        fallback: "Mediums could not be loaded. Try again.")
    }
  }

  private func create() async {
    guard canEdit else { return }
    busy = true
    errorMessage = nil
    defer { busy = false }
    do {
      let record: NamedRelationRecord = try await library.create(
        collection: "coloring_mediums", body: ListKind.medium.createBody(
          name: newName.trimmingCharacters(in: .whitespacesAndNewlines), userID: library.userID))
      options.append(record)
      options.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
      if selection.count < 99 { selection.insert(record.id) }
      else { errorMessage = "Medium added. Deselect one before attaching another; a page supports 99 mediums." }
      newName = ""
    } catch {
      errorMessage = error.userMessage(
        permission: "Your account cannot add a medium.",
        offline: APIError.needsConnection("Adding a medium"), fallback: "The medium could not be added.")
    }
  }

  private func save() async {
    guard canEdit, let baseline else { return }
    busy = true
    model.isMutating = true
    errorMessage = nil
    defer { busy = false; model.isMutating = false }
    do {
      _ = try await library.savePageMediums(
        pageID: page.id, baseline: baseline, selection: selection, connected: connectionAvailable)
      await model.load()
      await onCollectionChanged()
      AccessibilityNotification.Announcement("Mediums saved").post()
      dismiss()
    } catch {
      guard attempt != nil else {
        errorMessage = error.userMessage(
          permission: "Your account does not have permission to save this page.",
          fallback: "The page could not be saved. Try again.")
        return
      }
      errorMessage = error.userMessage(
        permission: "Sign in again to recover this medium save.",
        offline: "Reconnect to check the medium save. Your selection is kept on this device.",
        fallback: "The medium save needs review. Your selection is kept on this device.")
    }
  }
}
