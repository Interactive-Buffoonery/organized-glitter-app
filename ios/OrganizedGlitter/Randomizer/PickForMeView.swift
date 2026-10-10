import SwiftUI

struct PickForMeView: View {
  @Environment(\.theme) private var theme
  @Environment(\.dismiss) private var dismiss
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var model: LibraryRandomizer
  @State private var mode: RandomizerMode
  @State private var statuses = Dictionary(uniqueKeysWithValues:
    RandomizerMode.allCases.map { ($0, $0.defaultStatuses) })
  @State private var unavailableTarget = false

  let verticals: VerticalPreferences
  let onOpen: (LibraryItem) -> Void

  init(
    library: LibrarySession, initialSection: LibrarySection = .diamonds,
    verticals: VerticalPreferences, onOpen: @escaping (LibraryItem) -> Void
  ) {
    _model = State(initialValue: LibraryRandomizer(library: library))
    let requested = RandomizerMode.allCases.first { $0.section == initialSection } ?? .diamond
    _mode = State(initialValue: requested.isEnabled(for: verticals) ? requested
      : RandomizerMode.allCases.first { $0.isEnabled(for: verticals) } ?? requested)
    self.verticals = verticals
    self.onOpen = onOpen
  }

  var body: some View {
    let allCandidates = model.library.randomizerCandidates(mode: mode,
      statuses: Set(mode.section.statusOptions), verticals: verticals)
    let counts = Dictionary(grouping: allCandidates, by: { $0.item.status }).mapValues(\.count)
    let eligibleCount = allCandidates.filter { selectedStatuses.contains($0.item.status) }.count
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
          Picker("Pick from", selection: $mode) {
            ForEach(RandomizerMode.allCases.filter { $0.isEnabled(for: verticals) }) { mode in
              Text(mode.section.rawValue).tag(mode)
            }
          }
          .pickerStyle(.menu)
          .accessibilityIdentifier("pickForMe.mode")
          .disabled(model.isSelecting)

          Text("Include statuses")
            .font(.karla(.headline))
          ForEach(mode.section.statusOptions, id: \.self) { status in
            Toggle(isOn: statusBinding(status)) {
              VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Label(mode.section.statusLabel(status),
                  systemImage: mode.section.statusSystemImage(status))
                Text("\(counts[status, default: 0]) items")
                  .font(.karla(.caption))
                  .foregroundStyle(theme.pageSecondaryForeground)
              }
              .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("pickForMe.status.\(status)")
            .disabled(model.isSelecting)
          }

          Text("\(eligibleCount) eligible items")
            .font(.karla(.subheadline))
            .accessibilityIdentifier("pickForMe.count")
          if eligibleCount == 0 {
            Text(model.library.hasSnapshot
              ? "Turn on a status with items."
              : "Connect to download your library before picking.")
              .foregroundStyle(theme.pageSecondaryForeground)
              .fixedSize(horizontal: false, vertical: true)
          }

          Button(action: pick) {
            Label(model.selection == nil ? "Pick" : "Pick again", systemImage: "shuffle")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(QuietActionStyle())
          .disabled(eligibleCount == 0 || model.isSelecting)
          .accessibilityIdentifier("pickForMe.pick")

          if let selection = model.selection {
            result(selection)
              .id(selection.id)
              .transition(.opacity)
          }
          Text("Picks stay on this screen. Nothing is saved, and you can pick from your downloaded library offline.")
            .font(.karla(.footnote))
            .foregroundStyle(theme.pageSecondaryForeground)
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(theme.foreground)
        .padding()
        .frame(maxWidth: 600, alignment: .leading)
        .frame(maxWidth: .infinity)
      }
      .background { theme.themedBackground.ignoresSafeArea() }
      .navigationTitle("Pick for me")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .presentationSizing(.form)
    .onChange(of: mode) { _, _ in model.reset() }
    .onChange(of: verticals) { _, newValue in
      model.reset()
      if !mode.isEnabled(for: newValue),
        let available = RandomizerMode.allCases.first(where: { $0.isEnabled(for: newValue) }) {
        mode = available
      }
    }
    .onDisappear { model.reset() }
    .alert("Item unavailable", isPresented: $unavailableTarget) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("This item is no longer available in your library. Pick again to choose another item.")
    }
  }

  private var selectedStatuses: Set<String> { statuses[mode] ?? mode.defaultStatuses }

  private func statusBinding(_ status: String) -> Binding<Bool> {
    Binding(get: { selectedStatuses.contains(status) }, set: { included in
      if included { statuses[mode, default: []].insert(status) }
      else { statuses[mode, default: []].remove(status) }
      model.reset()
    })
  }

  private func pick() {
    if reduceMotion {
      if let id = model.beginSelection(mode: mode, statuses: selectedStatuses,
        verticals: verticals) { finishSelection(id: id) }
    } else {
      var selectionID: UUID?
      withAnimation(Theme.motion, completionCriteria: .logicallyComplete) {
        selectionID = model.beginSelection(mode: mode, statuses: selectedStatuses,
          verticals: verticals)
      } completion: {
        if let selectionID { finishSelection(id: selectionID) }
      }
    }
  }

  private func finishSelection(id: UUID) {
    model.finishSelection(id: id)
    if !model.isSelecting, let selection = model.selection, selection.id == id {
      AccessibilityNotification.Announcement("Picked \(selection.winner.title)").post()
    }
  }

  private func result(_ selection: RandomizerSelection) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
      Text("Your pick").font(.karla(.headline))
      LibraryGalleryCard(item: selection.winner.item,
        imageURL: protectedFiles?.artworkURL(for: selection.winner.item, thumb: ArtworkThumb.gallery),
        mode: .list)
        .accessibilityIdentifier("pickForMe.result")
      if let bookTitle = selection.winner.bookTitle {
        Text(bookTitle)
          .font(.karla(.subheadline))
          .foregroundStyle(theme.pageSecondaryForeground)
          .fixedSize(horizontal: false, vertical: true)
      }
      Button {
        guard let item = model.currentWinner(verticals: verticals) else {
          unavailableTarget = true
          return
        }
        onOpen(item)
        dismiss()
      } label: {
        Label("Open", systemImage: "arrow.right.circle")
      }
      .buttonStyle(QuietActionStyle())
      .disabled(model.isSelecting)
      .accessibilityIdentifier("pickForMe.open")
    }
  }
}
