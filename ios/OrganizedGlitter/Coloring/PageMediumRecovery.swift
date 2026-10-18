import SwiftUI

struct PageMediumRecovery: View {
  let library: LibrarySession
  let attempt: PageMediumAttempt
  var onResolved: @MainActor () async -> Void = {}
  @Environment(\.connectionAvailable) private var connectionAvailable
  @State private var busy = false
  @State private var errorMessage: String?
  @State private var confirmingDiscard = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(message).fixedSize(horizontal: false, vertical: true)
      Text("Your selection: \(MediumNames.summary(ids: Set(attempt.patch.mediums), options: options))")
        .fixedSize(horizontal: false, vertical: true)
      if let current = attempt.current {
        let accountSelection = MediumNames.summary(
          ids: current.selectedMediumIDs, options: current.expand?.mediums ?? options)
        Text("In your account: \(accountSelection)")
          .fixedSize(horizontal: false, vertical: true)
      }
      if let errorMessage { AccessibleErrorLabel(message: errorMessage) }
      if attempt.state == .awaitingReceipt {
        Button("Recover medium save") {
          run { _ = try await library.resumePageMediums(attempt.id, connected: connectionAvailable) }
        }
        .buttonStyle(.borderless)
        .disabled(busy || !connectionAvailable)
        .accessibilityIdentifier("mediums.recover")
        NeedsConnectionHint()
      } else {
        if attempt.state == .conflict, let baseline = attempt.current?.mediumIDs {
          Button("Reapply my selection") {
            run {
              _ = try await library.savePageMediums(
                pageID: attempt.pageID, baseline: baseline, selection: Set(attempt.patch.mediums),
                connected: connectionAvailable, replacing: attempt.id)
            }
          }
          .buttonStyle(.borderless)
          .disabled(busy || !connectionAvailable)
          .accessibilityIdentifier("mediums.reapply")
          NeedsConnectionHint()
        }
        Button("Discard this draft", role: .destructive) { confirmingDiscard = true }
          .buttonStyle(.borderless)
          .disabled(busy)
          .accessibilityIdentifier("mediums.discard")
      }
      if busy { ProgressView("Checking medium save…") }
    }
    .confirmationDialog("Discard this medium selection?", isPresented: $confirmingDiscard) {
      Button("Discard draft", role: .destructive) {
        run { try await library.discardPageMediums(attempt.id) }
      }
    } message: {
      Text("The medium selection saved on this device will be removed.")
    }
  }

  private var options: [NamedRelationRecord] {
    ListOptions.fromDownloadedLibrary(library.items, kind: .medium, userID: library.userID)
  }

  private var message: String {
    switch attempt.state {
    case .awaitingReceipt:
      "The result of this medium save needs checking. Recovery uses the same saved request; keep it until the service confirms the result."
    case .conflict:
      "Mediums changed on another device. Review the account selection before reapplying your draft."
    case .missing:
      "The service could not find this page. Your medium selection is still on this device."
    case .rejected:
      "The account could not accept this selection. Keep or discard the draft before editing again."
    case .integrityFailure:
      "This request could not be verified safely. Keep or discard the draft; do not retry it as a new save."
    }
  }

  private func run(_ operation: @escaping @MainActor () async throws -> Void) {
    guard !busy else { return }
    busy = true
    errorMessage = nil
    Task {
      defer { busy = false }
      do {
        try await operation()
        await onResolved()
        AccessibilityNotification.Announcement("Medium selection reviewed").post()
      } catch {
        errorMessage = error.userMessage(
          permission: "Sign in again to recover this medium save.",
          offline: "Reconnect to recover this medium save.",
          fallback: "The save is still being reviewed. Your selection remains on this device.")
      }
    }
  }
}

enum MediumNames {
  static func summary(ids: Set<String>, options: [NamedRelationRecord]) -> String {
    guard !ids.isEmpty else { return "None" }
    let names = options.filter { ids.contains($0.id) }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map(\.name)
    let unknown = ids.count - Set(options.map(\.id)).intersection(ids).count
    let unavailable = unknown == 0 ? [] : ["\(unknown) unavailable medium\(unknown == 1 ? "" : "s")"]
    return (names + unavailable).formatted(.list(type: .and))
  }
}
