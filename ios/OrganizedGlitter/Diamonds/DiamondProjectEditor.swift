import SwiftUI

struct DiamondProjectDraft: Equatable {
  var title: String
  var status: String
  var kitCategory: String
  var drillShape: String

  init(project: DiamondProjectRecord? = nil) {
    title = project?.title ?? ""
    status = project?.status ?? "wishlist"
    kitCategory = project?.kitCategory ?? "full"
    drillShape = project?.drillShape ?? (project == nil ? "round" : "")
  }

  var isValid: Bool {
    !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func matchesSavedRecord(_ record: DiamondProjectRecord) -> Bool {
    title.trimmingCharacters(in: .whitespacesAndNewlines) == record.title
      && status == record.status
      && kitCategory == record.kitCategory
      && drillShape == (record.drillShape ?? "")
  }
}

struct DiamondProjectEditor: View {
  let client: PocketBaseClient
  let userID: String
  let project: DiamondProjectRecord?
  let onLibraryRefresh: () async -> Void
  let onSaved: (DiamondProjectRecord) -> Void

  private let baseline: DiamondProjectDraft

  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @State private var draft: DiamondProjectDraft
  @State private var isSaving = false
  @State private var errorMessage: String?
  @State private var isCompletionUnknown = false

  init(
    client: PocketBaseClient,
    userID: String,
    project: DiamondProjectRecord? = nil,
    onLibraryRefresh: @escaping () async -> Void = {},
    onSaved: @escaping (DiamondProjectRecord) -> Void
  ) {
    self.client = client
    self.userID = userID
    self.project = project
    self.onLibraryRefresh = onLibraryRefresh
    self.onSaved = onSaved
    let initialDraft = DiamondProjectDraft(project: project)
    baseline = initialDraft
    _draft = State(initialValue: initialDraft)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Project") {
          TextField("Title", text: $draft.title)

          Picker("Status", selection: $draft.status) {
            ForEach(LibrarySection.diamonds.statusOptions, id: \.self) { status in
              Text(status.organizedGlitterLabel).tag(status)
            }
          }

          Picker("Kit", selection: $draft.kitCategory) {
            Text("Full size").tag("full")
            Text("Mini").tag("mini")
          }

          Picker("Drill shape", selection: $draft.drillShape) {
            Text("Not set").tag("")
            Text("Round").tag("round")
            Text("Square").tag("square")
          }
        }
        .listRowBackground(theme.card)

        if let errorMessage {
          Section {
            AccessibleErrorLabel(message: errorMessage)
              .accessibilityIdentifier("projectSaveError")
          }
          .listRowBackground(theme.card)
        }
      }
      .themedScrollBackground()
      .navigationTitle(project == nil ? "New Project" : "Edit Project")
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

    let write = DiamondProjectWrite.make(
      userID: userID,
      baseline: baseline,
      draft: draft,
      isCreate: project == nil
    )

    do {
      let saved: DiamondProjectRecord
      if let project {
        saved = try await client.update(
          collection: "projects",
          id: project.id,
          body: write
        )
      } else {
        saved = try await client.create(collection: "projects", body: write)
      }
      onSaved(saved)
      dismiss()
    } catch APIError.offline, APIError.server {
      await onLibraryRefresh()
      if let project,
        let refreshed: DiamondProjectRecord = try? await client.get(
          collection: "projects",
          id: project.id
        ),
        draft.matchesSavedRecord(refreshed)
      {
        onSaved(refreshed)
        dismiss()
        return
      }
      isCompletionUnknown = true
      errorMessage =
        "Save status is unknown. The library was refreshed; check the project before trying again."
    } catch {
      errorMessage = error.projectSaveMessage
    }
  }
}

// `user` is sent only on create; it is omitted on update so a save can never
// reassign ownership. `drillShape` is omitted on update when unchanged because
// the synthesized encoder drops nil keys, and a PATCH without `drill_shape`
// leaves the server value untouched. When the user clears drill shape, the key
// is included as `""`, PocketBase's unset value for a non-required select.
struct DiamondProjectWrite: Encodable {
  let user: String?
  let title: String?
  let status: String?
  let kitCategory: String?
  let drillShape: String?

  enum CodingKeys: String, CodingKey {
    case user, title, status
    case kitCategory = "kit_category"
    case drillShape = "drill_shape"
  }

  static func make(
    userID: String,
    baseline: DiamondProjectDraft,
    draft: DiamondProjectDraft,
    isCreate: Bool
  ) -> DiamondProjectWrite {
    let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    if isCreate {
      return DiamondProjectWrite(
        user: userID,
        title: trimmedTitle,
        status: draft.status,
        kitCategory: draft.kitCategory,
        drillShape: draft.drillShape
      )
    }

    let baselineTitle = baseline.title.trimmingCharacters(in: .whitespacesAndNewlines)
    return DiamondProjectWrite(
      user: nil,
      title: trimmedTitle != baselineTitle ? trimmedTitle : nil,
      status: draft.status != baseline.status ? draft.status : nil,
      kitCategory: draft.kitCategory != baseline.kitCategory ? draft.kitCategory : nil,
      drillShape: draft.drillShape != baseline.drillShape ? draft.drillShape : nil
    )
  }
}

extension Error {
  fileprivate var projectSaveMessage: String {
    switch self as? APIError {
    case .validation(let message):
      message
    case .forbidden:
      "Your account does not have permission to save this project."
    case .unauthenticated:
      "Your session has expired. Sign in again."
    default:
      "The project could not be saved. Try again."
    }
  }
}
