import SwiftUI

struct DiamondProjectDraft: Equatable {
  var title: String
  var status: String
  var kitCategory: String
  var drillShape: String

  var company: String
  var artist: String
  var tagIDs: Set<String>
  var width: String
  var height: String
  var totalDiamonds: String
  var colorCount: String
  var sourceURL: String
  var generalNotes: String

  init(project: DiamondProjectRecord? = nil) {
    company = project?.company ?? ""
    artist = project?.artist ?? ""
    tagIDs = Set(project?.tags.map(\.id) ?? [])
    width = Self.numberText(project?.width)
    height = Self.numberText(project?.height)
    totalDiamonds = Self.numberText(project?.totalDiamonds)
    colorCount = Self.numberText(project?.colorCount)
    sourceURL = project?.sourceURL ?? ""
    generalNotes = project?.generalNotes?.plainTextFromHTML ?? ""
    title = project?.title ?? ""
    status = project?.status ?? "wishlist"
    kitCategory = project?.kitCategory ?? "full"
    drillShape = project?.drillShape ?? (project == nil ? "round" : "")
  }

  var isValid: Bool {
    !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sizeValidationMessage == nil && sourceValidationMessage == nil
  }

  static func numberText(_ value: Double?) -> String {
    guard let value, value != 0 else { return "" }
    return value.formatted(.number.grouping(.never).precision(.fractionLength(0...10)))
  }

  static func number(_ text: String) -> Double? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return 0 }
    let separator = Locale.current.decimalSeparator ?? "."
    return Double(text.replacingOccurrences(of: separator, with: "."))
  }

  var sizeValidationMessage: String? {
    for (text, maximum, whole) in [
      (width, 1000.0, false), (height, 1000.0, false),
      (totalDiamonds, 2_000_000.0, true), (colorCount, 1000.0, true),
    ] {
      guard let value = Self.number(text), value.isFinite, value >= 0,
        value <= maximum, !whole || value.rounded() == value else {
        return "Use dimensions from 0 to 1,000 cm, up to 2,000,000 diamonds and 1,000 colors. Counts must be whole numbers."
      }
    }
    return nil
  }

  static func normalizedSourceURL(_ text: String) -> String? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return "" }
    guard !text.contains(where: { $0.isWhitespace }) else { return nil }
    let candidate = text.contains(":") ? text : "https://" + text
    guard let components = URLComponents(string: candidate),
      let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = components.host, !host.isEmpty, components.url != nil else { return nil }
    return candidate
  }

  var sourceValidationMessage: String? {
    Self.normalizedSourceURL(sourceURL) == nil ? "Enter a valid http or https link, or leave it empty." : nil
  }

  static func notesHTML(_ text: String) -> String {
    guard !text.isEmpty else { return "" }
    let escaped = text.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    return escaped.components(separatedBy: "\n\n")
      .map { "<p>" + $0.replacingOccurrences(of: "\n", with: "<br>") + "</p>" }
      .joined(separator: "\n")
  }

  func matchesSavedRecord(_ record: DiamondProjectRecord) -> Bool {
    let saved = Self(project: record)
    return title.trimmingCharacters(in: .whitespacesAndNewlines) == saved.title
      && status == saved.status && kitCategory == saved.kitCategory
      && drillShape == saved.drillShape && company == saved.company && artist == saved.artist
      && Self.number(width) == Self.number(saved.width)
      && Self.number(height) == Self.number(saved.height)
      && Self.number(totalDiamonds) == Self.number(saved.totalDiamonds)
      && Self.number(colorCount) == Self.number(saved.colorCount)
      && Self.normalizedSourceURL(sourceURL) == Self.normalizedSourceURL(saved.sourceURL)
      && generalNotes == saved.generalNotes
  }
}

struct DiamondProjectEditor: View {
  let library: LibrarySession
  var userID: String { library.userID }
  let project: DiamondProjectRecord?
  let onLibraryRefresh: () async -> Void
  let onSaved: (DiamondProjectRecord) -> Void

  private let baseline: DiamondProjectDraft

  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @Environment(\.protectedFiles) private var protectedFiles
  @State private var draft: DiamondProjectDraft
  @State private var coverChange: CoverChange = .unchanged
  @State private var triedTagIDs: Set<String> = []
  @State private var confirmedTagIDs: Set<String>
  @State private var savedRecord: DiamondProjectRecord?
  @State private var savedDraft: DiamondProjectDraft?
  @State private var isSaving = false
  @State private var errorMessage: String?

  init(
    library: LibrarySession,
    project: DiamondProjectRecord? = nil,
    onLibraryRefresh: @escaping () async -> Void = {},
    onSaved: @escaping (DiamondProjectRecord) -> Void
  ) {
    self.library = library
    self.project = project
    self.onLibraryRefresh = onLibraryRefresh
    self.onSaved = onSaved
    let initialDraft = DiamondProjectDraft(project: project)
    baseline = initialDraft
    _draft = State(initialValue: initialDraft)
    _confirmedTagIDs = State(initialValue: initialDraft.tagIDs)
  }

  private var currentCoverURL: URL? {
    guard let project = savedRecord ?? project, let image = project.image?.nonEmpty else {
      return nil
    }
    return protectedFiles?.url(collection: "projects", recordID: project.id, filename: image)
  }

  private func numberField(
    _ label: String, unit: String? = nil, text: Binding<String>, keyboard: UIKeyboardType
  ) -> some View {
    LabeledContent(unit.map { "\(label) (\($0))" } ?? label) {
      TextField("Not set", text: text)
        .keyboardType(keyboard)
        .multilineTextAlignment(.trailing)
        .accessibilityLabel(unit == nil ? label : "\(label) in centimeters")
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        Group {
          CoverImageSection(
            currentCoverURL: currentCoverURL,
            placeholderSystemImage: "photo",
            accessibilityNoun: "Project photo", change: $coverChange)

          Section("Project") {
            TextField("Title", text: $draft.title)

            Picker("Status", selection: $draft.status) {
              ForEach(DiamondStatus.allCases, id: \.self) { status in
                Text(status.label).tag(status.rawValue)
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

          Section("Credits") {
            ListPicker(library: library, userID: userID, kind: .company,
              initialName: project?.expand?.company?.name, selection: $draft.company)
            ListPicker(library: library, userID: userID, kind: .artist,
              initialName: project?.expand?.artist?.name, selection: $draft.artist)
            TagPicker(library: library, userID: userID, kind: .diamondTag, selection: $draft.tagIDs)
          }

          Section {
            numberField("Width", unit: "cm", text: $draft.width, keyboard: .decimalPad)
            numberField("Height", unit: "cm", text: $draft.height, keyboard: .decimalPad)
            numberField("Diamonds", text: $draft.totalDiamonds, keyboard: .numberPad)
            numberField("Colors", text: $draft.colorCount, keyboard: .numberPad)
          } header: {
            Text("Size")
          } footer: {
            if let message = draft.sizeValidationMessage {
              AccessibleErrorLabel(message: message)
            }
          }

          Section {
            TextField("Source link", text: $draft.sourceURL)
              .keyboardType(.URL)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
          } footer: {
            if let message = draft.sourceValidationMessage {
              AccessibleErrorLabel(message: message)
            }
          }

          Section("Notes") {
            TextField("General notes", text: $draft.generalNotes, axis: .vertical)
              .lineLimit(4...12)
          }

          if project == nil || draft.tagIDs != baseline.tagIDs || coverChange != .unchanged {
            Section { NeedsConnectionHint() }
          }

          if let errorMessage {
            Section {
              AccessibleErrorLabel(message: errorMessage)
                .accessibilityIdentifier("projectSaveError")
            }
          }
        }
        .listRowBackground(theme.card)
      }
      .disabled(isSaving)
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
          .disabled(!draft.isValid || isSaving)
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

    let submittedDraft = draft
    let writeBaseline = savedDraft ?? baseline
    let target = savedRecord ?? project
    let write = DiamondProjectWrite.make(
      userID: userID, baseline: writeBaseline, draft: submittedDraft,
      isCreate: target == nil)

    do {
      let saved: DiamondProjectRecord
      if let target {
        if write.hasChanges {
          saved = try await library.update(collection: "projects", id: target.id, body: write)
        } else {
          saved = target
        }
      } else {
        saved = try await library.create(collection: "projects", body: write)
      }
      savedRecord = saved
      savedDraft = submittedDraft
      do {
        if submittedDraft.tagIDs != confirmedTagIDs {
          let submittedTags = submittedDraft.tagIDs
          let previousTags = baseline.tagIDs.union(triedTagIDs)
          triedTagIDs.formUnion(submittedTags)
          try await TagLinks.sync(
            kind: .diamondTag, recordID: saved.id,
            from: previousTags, to: submittedTags, library: library)
          confirmedTagIDs = submittedTags
        }
      } catch APIError.cancelled {
        return
      } catch is CancellationError {
        return
      } catch {
        errorMessage = "The project was saved, but tags could not be saved. Check your connection and try again."
        return
      }
      if coverChange != .unchanged {
        do {
          savedRecord = try await CoverUpload.apply(
            coverChange, collection: "projects", recordID: saved.id,
            field: "image", library: library)
          coverChange = .unchanged
        } catch APIError.cancelled {
          return
        } catch is CancellationError {
          return
        } catch {
          errorMessage = "The project was saved, but the photo could not be uploaded. Try again."
          return
        }
      }
      let refreshed = library.items.compactMap { item -> DiamondProjectRecord? in
        guard case .diamond(let record) = item, record.id == saved.id else { return nil }
        return record
      }.first
      onSaved(refreshed ?? savedRecord ?? saved)
      dismiss()
    } catch APIError.cancelled {
      return
    } catch is CancellationError {
      return
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
struct DiamondProjectWrite: Encodable, Sendable {
  let user: String?
  let title: String?
  let status: String?
  let kitCategory: String?
  let drillShape: String?
  let company: String?
  let artist: String?
  let width: Double?
  let height: Double?
  let totalDiamonds: Double?
  let colorCount: Double?
  let sourceURL: String?
  let generalNotes: String?

  enum CodingKeys: String, CodingKey {
    case user, title, status
    case kitCategory = "kit_category"
    case drillShape = "drill_shape"
    case company, artist, width, height
    case totalDiamonds = "total_diamonds"
    case colorCount = "color_count"
    case sourceURL = "source_url"
    case generalNotes = "general_notes"
  }

  var hasChanges: Bool {
    user != nil || title != nil || status != nil || kitCategory != nil || drillShape != nil
      || company != nil || artist != nil || width != nil || height != nil
      || totalDiamonds != nil || colorCount != nil || sourceURL != nil || generalNotes != nil
  }

  static func make(
    userID: String,
    baseline: DiamondProjectDraft,
    draft: DiamondProjectDraft,
    isCreate: Bool
  ) -> DiamondProjectWrite {
    let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let baselineTitle = baseline.title.trimmingCharacters(in: .whitespacesAndNewlines)
    return DiamondProjectWrite(
      user: isCreate ? userID : nil,
      title: isCreate || title != baselineTitle ? title : nil,
      status: isCreate || draft.status != baseline.status ? draft.status : nil,
      kitCategory: isCreate || draft.kitCategory != baseline.kitCategory ? draft.kitCategory : nil,
      drillShape: isCreate || draft.drillShape != baseline.drillShape ? draft.drillShape : nil,
      company: isCreate || draft.company != baseline.company ? draft.company : nil,
      artist: isCreate || draft.artist != baseline.artist ? draft.artist : nil,
      width: isCreate || DiamondProjectDraft.number(draft.width) != DiamondProjectDraft.number(baseline.width)
        ? DiamondProjectDraft.number(draft.width) : nil,
      height: isCreate || DiamondProjectDraft.number(draft.height) != DiamondProjectDraft.number(baseline.height)
        ? DiamondProjectDraft.number(draft.height) : nil,
      totalDiamonds: isCreate || DiamondProjectDraft.number(draft.totalDiamonds) != DiamondProjectDraft.number(baseline.totalDiamonds)
        ? DiamondProjectDraft.number(draft.totalDiamonds) : nil,
      colorCount: isCreate || DiamondProjectDraft.number(draft.colorCount) != DiamondProjectDraft.number(baseline.colorCount)
        ? DiamondProjectDraft.number(draft.colorCount) : nil,
      sourceURL: isCreate || DiamondProjectDraft.normalizedSourceURL(draft.sourceURL) != DiamondProjectDraft.normalizedSourceURL(baseline.sourceURL)
        ? DiamondProjectDraft.normalizedSourceURL(draft.sourceURL) : nil,
      generalNotes: isCreate || draft.generalNotes != baseline.generalNotes
        ? DiamondProjectDraft.notesHTML(draft.generalNotes) : nil
    )
  }
}

extension Error {
  fileprivate var projectSaveMessage: String {
    userMessage(
      permission: "Your account does not have permission to save this project.",
      offline: APIError.needsConnection("Creating a project"),
      fallback: "The project could not be saved. Try again."
    )
  }
}
