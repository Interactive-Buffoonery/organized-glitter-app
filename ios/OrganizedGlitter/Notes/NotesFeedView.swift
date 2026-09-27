import SwiftUI

/// Notes from every enabled craft, grouped by the date the maker chose.
struct NotesFeedView: View {
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.theme) private var theme

  let library: LibrarySession
  let verticals: VerticalPreferences

  @State private var craft: NotesCraft = .all
  @State private var year: Int?
  @State private var isPickingTarget = false
  @State private var loadMessage: String?

  var body: some View {
    let visibleCraft = craft.visible(for: verticals)
    let allEntries = NotesFeed.entries(
      items: library.items, diamondNotes: library.progressNotes,
      coloringNotes: library.coloringPageProgressNotes)
    let craftEntries = NotesFeed.filter(allEntries, craft: visibleCraft, year: nil)
    let years = NotesFeed.years(in: craftEntries)
    let entries = NotesFeed.filter(craftEntries, craft: .all, year: year)
    let photos = entries.compactMap { entry -> DetailPhoto? in
      guard
        let thumbnail = protectedFiles?.photoURL(for: entry.note, thumb: ArtworkThumb.gallery),
        let fullSize = protectedFiles?.photoURL(for: entry.note)
      else { return nil }
      return DetailPhoto(
        id: entry.id, url: thumbnail, fullSizeURL: fullSize,
        accessibilityLabel: "Progress photo for \(entry.contextTitle)",
        date: DetailDateOnly.formatted(entry.note.date),
        caption: entry.note.content.nonEmpty)
    }

    ScrollView {
      LazyVStack(alignment: .leading, spacing: 20) {
        if verticals.diamondPainting && verticals.coloringBooks {
          Picker("Craft", selection: $craft) {
            ForEach(NotesCraft.allCases) { Text($0.title).tag($0) }
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("notes.craft")
        }

        if !library.hasSnapshot {
          if library.isSyncing && loadMessage == nil {
            ProgressView("Loading notes")
              .frame(maxWidth: .infinity, minHeight: 280)
          } else {
            ContentUnavailableView {
              Label("Couldn’t load notes", systemImage: "exclamationmark.triangle")
            } description: {
              Text(loadMessage ?? library.syncMessage ?? "Connect to download your notes.")
            } actions: {
              Button("Try Again") { Task { await refresh() } }
            }
            .frame(maxWidth: .infinity, minHeight: 280)
          }
        } else {
          if let loadMessage {
            AccessibleErrorLabel(message: loadMessage)
          }
          if entries.isEmpty {
            emptyState(craft: visibleCraft)
          } else {
            ForEach(NotesFeed.months(entries)) { month in
              Section {
                ForEach(month.entries) { entry in
                  VStack(alignment: .leading, spacing: 8) {
                    NavigationLink(value: entry.target) {
                      Label(entry.contextTitle, systemImage: entry.craft == .diamond ? "diamond" : "paintpalette")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityLabel("Open \(entry.contextTitle)")
                    .accessibilityIdentifier("notes.entry.\(entry.note.recordID)")

                    ProgressNoteEntry(
                      note: entry.note,
                      photoURL: protectedFiles?.photoURL(
                        for: entry.note, thumb: ArtworkThumb.gallery))
                  }
                }
              } header: {
                Text(month.title())
                  .font(.title3.weight(.semibold))
                  .foregroundStyle(theme.foreground)
                  .accessibilityAddTraits(.isHeader)
                  .padding(.top, 8)
              }
            }
          }
        }
      }
      .frame(maxWidth: 600, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity)
    }
    .photoViewer(photos)
    .background { theme.themedBackground.ignoresSafeArea() }
    .refreshable { await refresh() }
    .navigationTitle("Notes")
    .accessibilityIdentifier("notes.feed")
    .toolbar {
      if years.count > 1 {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Picker("Year", selection: $year) {
              Text("All years").tag(Int?.none)
              ForEach(years, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
            }
          } label: {
            Label(year.map(String.init) ?? "All years", systemImage: "calendar")
          }
          .accessibilityLabel("Filter notes by year")
          .accessibilityValue(year.map(String.init) ?? "All years")
          .accessibilityIdentifier("notes.year")
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button("Add progress note", systemImage: "square.and.pencil") { isPickingTarget = true }
          .disabled(!verticals.hasEnabledVertical)
          .accessibilityIdentifier("notes.add")
      }
    }
    .onChange(of: craft) { _, _ in year = nil }
    .onChange(of: years) { _, available in
      if let year, !available.contains(year) { self.year = nil }
    }
    .inspector(isPresented: $isPickingTarget) {
      NoteTargetPicker(library: library, verticals: verticals)
    }
    .task {
      do { try await library.loadLocal() }
      catch is CancellationError { }
      catch { loadMessage = "Notes couldn’t load. Try again shortly." }
    }
  }

  private func emptyState(craft: NotesCraft) -> some View {
    let description = switch craft {
    case .all: "Add a progress note to a diamond painting or coloring page, and it will show up here."
    case .diamond: "Add a progress note to a diamond painting, and it will show up here."
    case .coloring: "Add a progress note to a coloring page, and it will show up here."
    }
    return ContentUnavailableView {
      Label("Start logging progress", systemImage: "book.pages")
    } description: {
      Text(year.map { "No notes from \($0)." } ?? description)
    } actions: {
      if year == nil, verticals.hasEnabledVertical {
        Button("Add a progress note") { isPickingTarget = true }
          .buttonStyle(.borderedProminent)
          .tint(theme.primary)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 360)
    .accessibilityIdentifier("notes.empty")
  }

  private func refresh() async {
    do {
      try await library.refresh(force: true)
      loadMessage = nil
    } catch APIError.cancelled {
    } catch is CancellationError {
    } catch APIError.offline {
      loadMessage = "You’re offline. Showing your downloaded notes."
    } catch {
      loadMessage = library.syncMessage ?? "Notes couldn’t refresh. Try again shortly."
    }
  }
}
