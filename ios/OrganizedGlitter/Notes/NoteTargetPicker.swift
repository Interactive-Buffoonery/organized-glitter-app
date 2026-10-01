import SwiftUI

struct NoteTargetPicker: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.theme) private var theme

  let library: LibrarySession
  let verticals: VerticalPreferences
  var onSaved: () async -> Void = {}

  @State private var search = ""
  @State private var editor: LibraryItemDetailModel?
  @State private var loadMessage: String?

  var body: some View {
    Group {
      if let editor {
        ProgressNoteEditor(
          model: editor,
          onCollectionChanged: {
            try? await library.loadLocal()
            await onSaved()
          }
        )
      } else {
        targetList
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    .task {
      do { try await library.loadLocal() }
      catch is CancellationError, APIError.cancelled { }
      catch { loadMessage = "Projects and pages couldn’t load. Try again shortly." }
    }
  }

  private var targetList: some View {
    let targets = NotesFeed.noteTargets(items: library.items, verticals: verticals, search: search)
    let inProgress = targets.filter(\.isInProgress)
    let other = targets.filter { !$0.isInProgress }

    return NavigationStack {
      List {
        if let loadMessage, library.hasSnapshot {
          AccessibleErrorLabel(message: loadMessage)
        }

        if !library.hasSnapshot {
          ContentUnavailableView {
            Label("Library unavailable", systemImage: "wifi.slash")
          } description: {
            Text(loadMessage ?? library.syncMessage ?? "Connect to download your projects and pages.")
          }
          .listRowBackground(Color.clear)
        } else if targets.isEmpty {
          ContentUnavailableView {
            Label(search.isEmpty ? "No projects or pages" : "No matches", systemImage: "magnifyingglass")
          } description: {
            Text(search.isEmpty
              ? "Add a diamond painting project or coloring page before logging progress."
              : "Try another project or page name.")
          }
            .listRowBackground(Color.clear)
        } else {
          if !inProgress.isEmpty {
            Section("In progress") {
              ForEach(inProgress) { target in targetRow(target) }
            }
          }
          if !other.isEmpty {
            Section("Other projects and pages") {
              ForEach(other) { target in targetRow(target) }
            }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background { theme.themedBackground.ignoresSafeArea() }
      .navigationTitle("Choose where to log")
      .navigationBarTitleDisplayMode(.inline)
      .searchable(text: $search, prompt: "Search projects and pages")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
      .accessibilityIdentifier("notes.targetPicker")
    }
  }

  private func targetRow(_ target: NoteTarget) -> some View {
    Button {
      editor = LibraryItemDetailModel(item: target.item, library: library)
    } label: {
      HStack(spacing: 12) {
        CoverArtwork(
          item: target.item,
          url: protectedFiles?.artworkURL(for: target.item, thumb: ArtworkThumb.gallery),
          maxPixelDimension: 240
        )
        .frame(width: 48, height: 60)
        .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 4) {
          Text(target.title)
            .font(.karla(.body).weight(.semibold))
            .foregroundStyle(theme.foreground)
            .multilineTextAlignment(.leading)
          Text(target.subtitle)
            .font(.karla(.subheadline))
            .foregroundStyle(theme.pageSecondaryForeground)
            .multilineTextAlignment(.leading)
        }
        Spacer(minLength: 0)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Log progress for \(target.title), \(target.subtitle)")
    .accessibilityIdentifier("notes.target.\(target.item.recordID)")
  }
}
