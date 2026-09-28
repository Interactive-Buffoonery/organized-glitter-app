import SwiftUI

/// Status as a menu button: the current value is the label, the choices check-mark it.
struct DetailStatusMenu<Status: RecordStatus>: View {
  @Environment(FormDrawer.self) private var formDrawer
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let current: String
  let model: LibraryItemDetailModel
  let onCollectionChanged: @MainActor @Sendable () async -> Void

  var body: some View {
    let palette = DetailStatusAppearance.palette(for: current, colorScheme: colorScheme)
    Menu {
      Picker(
        "Status",
        selection: Binding(get: { current }, set: { select($0) })
      ) {
        ForEach(Status.allCases, id: \.rawValue) { status in
          Label(status.label, systemImage: status.systemImage)
            .tag(status.rawValue)
        }
      }
    } label: {
      HStack(spacing: 6) {
        Label {
          Text(Status.label(for: current))
        } icon: {
          if reduceMotion {
            Image(systemName: Status.systemImage(for: current))
          } else {
            Image(systemName: Status.systemImage(for: current))
              .symbolEffect(.bounce, options: .nonRepeating, value: model.statusSaveRevision)
          }
        }
        .labelStyle(.titleAndIcon)
        Image(systemName: "chevron.down")
          .font(.caption.weight(.semibold))
          .accessibilityHidden(true)
      }
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(palette.foreground)
      .padding(.horizontal, 14)
      .padding(.vertical, 7)
      .background(palette.background, in: .capsule)
      .fixedSize(horizontal: false, vertical: true)
      .frame(minHeight: 44)
      .contentShape(.rect)
    }
    .sensoryFeedback(.success, trigger: model.statusSaveRevision)
    .disabledWhileFormPresented(
      formDrawer, or: model.isMutating || model.unresolvedWriteState != nil)
    .accessibilityLabel("Status")
    .accessibilityValue(Status.label(for: current))
    .accessibilityIdentifier("detail.status")
  }

  private func select(_ status: String) {
    guard !formDrawer.isPresenting else { return }
    Task {
      let changed = await model.setStatus(status)
      if changed || (model.unresolvedStatusWrite && model.unresolvedWriteState == .refreshed) {
        await onCollectionChanged()
      }
    }
  }
}

/// Soft status pairs follow the web app's status color families.
enum DetailStatusAppearance {
  static func palette(
    for status: String, colorScheme: ColorScheme
  ) -> (foreground: Color, background: Color) {
    let (light, lightBackground, dark, darkBackground): (UInt32, UInt32, UInt32, UInt32) =
      switch status {
      case "wishlist", "destashed": (0x9F1239, 0xFFE4E6, 0xFFE4E6, 0x6B2138)
      case "purchased": (0x075985, 0xE0F2FE, 0xD9F2FF, 0x164E63)
      case "stash", "in_stash": (0x9A3412, 0xFFEDD5, 0xFFEDD5, 0x7C2D12)
      case "kitted", "palette_chosen": (0x115E59, 0xCCFBF1, 0xCCFBF1, 0x134E4A)
      case "progress", "in_progress": (0x6B21A8, 0xEAD7FF, 0xF3E8FF, 0x581C87)
      case "onhold", "on_hold": (0x92400E, 0xFEF3C7, 0xFEF3C7, 0x78350F)
      case "completed": (0x065F46, 0xD1FAE5, 0xD1FAE5, 0x064E3B)
      default: (0x374151, 0xE5E7EB, 0xE5E7EB, 0x374151)
      }
    return colorScheme == .dark
      ? (Color(hex: dark), Color(hex: darkBackground))
      : (Color(hex: light), Color(hex: lightBackground))
  }
}

struct DetailStatusRecovery: View {
  let model: LibraryItemDetailModel
  let onCollectionChanged: @MainActor @Sendable () async -> Void

  var body: some View {
    if let message = model.editErrorMessage {
      AccessibleErrorLabel(message: message)
    }
    if model.unresolvedStatusWrite {
      VStack(alignment: .leading, spacing: 8) {
        if let message = model.mutationErrorMessage {
          AccessibleErrorLabel(message: message)
        }
        switch model.unresolvedWriteState {
        case .needsRefresh:
          Button("Refresh status") {
            Task {
              if await model.refreshUnresolvedWriteStatus() {
                await onCollectionChanged()
              }
            }
          }
          .disabled(model.isMutating)
          .accessibilityIdentifier("detail.status.refresh")
        case .refreshed:
          Button("Done reviewing status") {
            model.clearUnresolvedWriteRecovery()
          }
          .accessibilityIdentifier("detail.status.reviewed")
        case nil:
          EmptyView()
        }
      }
      .buttonStyle(.bordered)
    }
  }
}

struct DetailSpec: Identifiable {
  struct Choice {
    struct Option {
      let value: String
      let label: String
    }

    let title: String
    let options: [Option]
    let selection: String
    let onSelect: (String) -> Void
  }

  let title: String
  let value: String
  let caption: String?
  let accessibilityValue: String
  /// Non-empty makes the cell a menu of inline pickers, like the status menu.
  var choices: [Choice] = []

  var id: String { title }
}

/// App Store-style info row. Falls back to labeled rows at accessibility sizes.
struct DetailSpecStrip: View {
  @Environment(FormDrawer.self) private var formDrawer
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.theme) private var theme

  let specs: [DetailSpec]
  var isDisabled = false

  var body: some View {
    if dynamicTypeSize.isAccessibilitySize {
      DetailMetadataCard {
        ForEach(specs) { spec in
          let value = [spec.value, spec.caption].compactMap { $0 }.joined(separator: ", ")
          if spec.choices.isEmpty {
            DetailMetadataRow(label: spec.title.capitalized, value: value)
          } else {
            DetailMetadataRow(label: spec.title.capitalized, combinesChildren: false) {
              choiceMenu(spec) {
                valueLabel(value, isEditable: true)
                  .foregroundStyle(theme.pageAction)
              }
            }
          }
        }
      }
      .accessibilityIdentifier("detail.specs")
    } else {
      HStack(alignment: .top, spacing: 0) {
        ForEach(Array(specs.enumerated()), id: \.element.id) { index, spec in
          if index > 0 {
            Divider().frame(height: 44)
          }
          if spec.choices.isEmpty {
            cell(spec)
          } else {
            choiceMenu(spec) { cell(spec) }
          }
        }
      }
      .padding(.vertical, 12)
      .overlay(alignment: .top) { Divider() }
      .overlay(alignment: .bottom) { Divider() }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("detail.specs")
    }
  }

  private func cell(_ spec: DetailSpec) -> some View {
    VStack(spacing: 2) {
      Text(spec.title.uppercased())
        .font(.caption2.weight(.medium))
        .foregroundStyle(theme.pageSecondaryForeground)
      valueLabel(spec.value, isEditable: !spec.choices.isEmpty)
        .font(.headline)
        .foregroundStyle(theme.foreground)
      if let caption = spec.caption {
        Text(caption)
          .font(.caption2)
          .foregroundStyle(theme.pageSecondaryForeground)
      }
    }
    .lineLimit(1)
    .minimumScaleFactor(0.8)
    .frame(maxWidth: .infinity, minHeight: 44)
    .contentShape(.rect)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(spec.title.capitalized)
    .accessibilityValue(spec.accessibilityValue)
  }

  private func valueLabel(_ value: String, isEditable: Bool) -> some View {
    HStack(spacing: 3) {
      Text(value)
      if isEditable {
        Image(systemName: "chevron.down")
          .font(.caption2.weight(.bold))
          .foregroundStyle(theme.pageAction)
          .accessibilityHidden(true)
      }
    }
  }

  private func choiceMenu<Label: View>(
    _ spec: DetailSpec, @ViewBuilder label: () -> Label
  ) -> some View {
    Menu {
      ForEach(spec.choices, id: \.title) { choice in
        Picker(
          choice.title,
          selection: Binding(
            get: { choice.selection },
            set: { value in
              guard !formDrawer.isPresenting, !isDisabled else { return }
              choice.onSelect(value)
            }
          )
        ) {
          ForEach(choice.options, id: \.value) { option in
            Text(option.label).tag(option.value)
          }
        }
        .pickerStyle(.inline)
      }
    } label: {
      label()
    }
    .buttonStyle(.plain)
    .disabledWhileFormPresented(formDrawer, or: isDisabled)
    .accessibilityLabel(spec.title.capitalized)
    .accessibilityValue(spec.accessibilityValue)
    .accessibilityHint("Opens choices")
    .accessibilityIdentifier("detail.spec.\(spec.title.lowercased())")
  }
}

/// A title that becomes a text field when tapped, saved through `updateFields`.
/// `value` is the stored field; `placeholder` is shown while it is empty.
struct DetailInlineTitle: View {
  @Environment(FormDrawer.self) private var formDrawer
  @Environment(\.theme) private var theme

  let value: String
  var placeholder = ""
  let field: String
  let label: String
  var allowsEmpty = false
  let model: LibraryItemDetailModel
  let onCollectionChanged: @MainActor @Sendable () async -> Void

  @State private var draft = ""
  @State private var isEditing = false
  @FocusState private var isFocused: Bool

  var body: some View {
    if isEditing {
      TextField(label, text: $draft, prompt: Text(placeholder.nonEmpty ?? label))
        .font(.title2.bold())
        .foregroundStyle(theme.foreground)
        .disabledWhileFormPresented(
          formDrawer, or: model.isMutating || model.unresolvedWriteState != nil)
        .focused($isFocused)
        .submitLabel(.done)
        .onSubmit(commit)
        .onChange(of: isFocused) { _, focused in
          if !focused { commit() }
        }
        .onAppear { isFocused = true }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
        .accessibilityLabel(label)
        .accessibilityIdentifier("detail.title.field")
    } else {
      Button {
        draft = value
        isEditing = true
      } label: {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(value.nonEmpty ?? placeholder)
            .font(.title2.bold())
            .foregroundStyle(theme.foreground)
          Image(systemName: "pencil")
            .font(.body.weight(.semibold))
            .foregroundStyle(theme.pageAction)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .disabledWhileFormPresented(
        formDrawer, or: model.isMutating || model.unresolvedWriteState != nil)
      .accessibilityLabel(value.nonEmpty ?? placeholder)
      .accessibilityHint("Double-tap to change the \(label.lowercased())")
      .accessibilityAddTraits(.isHeader)
      .accessibilityIdentifier("detail.title")
    }
  }

  private func commit() {
    guard isEditing, !formDrawer.isPresenting else { return }
    isEditing = false
    guard !model.isMutating, model.unresolvedWriteState == nil else { return }
    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed != value, allowsEmpty || !trimmed.isEmpty else { return }
    saveDetailChange(
      { await model.updateFields([field: trimmed]) },
      onCollectionChanged: onCollectionChanged)
  }
}

@MainActor
func saveDetailChange(
  _ write: @escaping @MainActor () async -> Bool,
  onCollectionChanged: @escaping @MainActor @Sendable () async -> Void
) {
  Task {
    if await write() {
      await onCollectionChanged()
    }
  }
}
