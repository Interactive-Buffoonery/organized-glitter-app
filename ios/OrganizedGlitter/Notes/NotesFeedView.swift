import SwiftUI

/// Notes from every enabled craft, grouped by the date the maker chose.
struct NotesFeedView: View {
  @Environment(FormDrawer.self) private var formDrawer
  @Environment(\.locale) private var locale
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.theme) private var theme
  @Environment(\.timeZone) private var timeZone

  let library: LibrarySession
  let verticals: VerticalPreferences
  let onAddNote: () -> Void

  @State private var craft: NotesCraft = .all
  @State private var year: Int?
  @State private var loadMessage: String?
  @State private var allEntries: [NotesFeedEntry] = []
  @State private var sections: [NotesFeedSection] = []
  @State private var years: [Int] = []
  @State private var photos: [DetailPhoto] = []

  var body: some View {
    let availableCrafts = NotesCraft.available(for: verticals)
    let visibleCraft = craft.resolved(for: verticals)

    ScrollView {
      LazyVStack(alignment: .leading, spacing: 20) {
        if availableCrafts.count > 1 {
          Picker("Craft", selection: $craft) {
            ForEach(availableCrafts) { Text($0.title).tag($0) }
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
          if sections.isEmpty {
            emptyState(craft: visibleCraft)
          } else {
            ForEach(sections) { month in
              Section {
                ForEach(month.entries) { entry in
                  VStack(alignment: .leading, spacing: 8) {
                    NavigationLink(value: entry.target) {
                      HStack(spacing: 10) {
                        Image(systemName: entry.craft == .diamond
                          ? LibrarySection.diamonds.systemImage : LibrarySection.pages.systemImage)
                          .font(.karla(.subheadline).weight(.medium))
                          .symbolRenderingMode(.hierarchical)
                          .foregroundStyle(theme.primary)
                          .frame(width: 32, height: 32)
                          .background(theme.primary.opacity(0.10), in: .rect(cornerRadius: 8))
                          .accessibilityHidden(true)
                        Text(entry.contextTitle)
                          .font(.karla(.subheadline).weight(.semibold))
                          .foregroundStyle(theme.foreground)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                          .font(.karla(.caption).weight(.semibold))
                          .foregroundStyle(theme.pageSecondaryForeground)
                          .accessibilityHidden(true)
                      }
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
                Text(month.title)
                  .font(.karla(.title3).weight(.semibold))
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
        Button("Add progress note", systemImage: "square.and.pencil", action: onAddNote)
          .disabledWhileFormPresented(formDrawer)
          .disabled(availableCrafts.isEmpty)
          .accessibilityIdentifier("notes.add")
      }
    }
    .onChange(of: craft) { _, _ in year = nil; updateVisible() }
    .onChange(of: year) { _, _ in updateVisible() }
    .onChange(of: verticals) { _, _ in
      let selected = craft.resolved(for: verticals) ?? .all
      if selected != craft {
        craft = selected
        year = nil
      }
      updateVisible()
    }
    .onChange(of: protectedFiles?.token) { _, _ in updatePhotos() }
    .onChange(of: locale) { _, _ in updateVisible() }
    .onChange(of: timeZone) { _, _ in updatePhotos() }
    .task(id: library.generation) {
      do {
        try await library.loadLocal()
        loadMessage = nil
      } catch is CancellationError {
        return
      } catch {
        loadMessage = "Notes couldn’t load. Try again shortly."
        return
      }
      allEntries = NotesFeed.entries(
        items: library.items, diamondNotes: library.progressNotes,
        coloringNotes: library.coloringPageProgressNotes)
      updateVisible()
    }
  }

  private func updateVisible() {
    let craftEntries = NotesFeed.filter(
      allEntries, craft: craft, year: nil, verticals: verticals)
    let availableYears = NotesFeed.years(in: craftEntries)
    years = availableYears
    let selectedYear = year.flatMap { availableYears.contains($0) ? $0 : nil }
    if selectedYear != year { year = selectedYear }
    let visibleEntries = craftEntries.filter { selectedYear == nil || $0.year == selectedYear }
    sections = NotesFeed.months(visibleEntries).map {
      NotesFeedSection(id: $0.id, title: $0.title(locale: locale), entries: $0.entries)
    }
    updatePhotos(entries: visibleEntries)
  }

  private func updatePhotos(entries: [NotesFeedEntry]? = nil) {
    let entries = entries ?? sections.flatMap(\.entries)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let parser = DateFormatter()
    parser.calendar = calendar
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.timeZone = timeZone
    parser.dateFormat = "yyyy-MM-dd"
    parser.isLenient = false
    let display = DateFormatter()
    display.calendar = calendar
    display.locale = locale
    display.timeZone = timeZone
    display.dateStyle = .medium
    display.timeStyle = .none

    photos = entries.compactMap { entry -> DetailPhoto? in
      guard
        let thumbnail = protectedFiles?.photoURL(for: entry.note, thumb: ArtworkThumb.gallery),
        let fullSize = protectedFiles?.photoURL(for: entry.note)
      else { return nil }
      let source = String(entry.note.date.prefix(10))
      let date = parser.date(from: source).flatMap {
        parser.string(from: $0) == source ? display.string(from: $0) : nil
      }
      return DetailPhoto(
        id: entry.id, url: thumbnail, fullSizeURL: fullSize,
        accessibilityLabel: "Progress photo for \(entry.contextTitle)",
        date: date, caption: entry.note.content.nonEmpty)
    }
  }

  private func emptyState(craft: NotesCraft?) -> some View {
    let description = switch craft {
    case nil: "Enable a craft in account settings to start logging progress."
    case .all: "Add a progress note to a diamond painting or coloring page, and it will show up here."
    case .diamond: "Add a progress note to a diamond painting, and it will show up here."
    case .coloring: "Add a progress note to a coloring page, and it will show up here."
    }
    return ContentUnavailableView {
      Label("Start logging progress", systemImage: "note.text")
    } description: {
      Text(year.map { "No notes from \($0)." } ?? description)
    } actions: {
      if year == nil, !NotesCraft.available(for: verticals).isEmpty {
        Button("Add a progress note", action: onAddNote)
          .disabledWhileFormPresented(formDrawer)
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
      loadMessage = library.hasSnapshot
        ? "You’re offline. Showing your downloaded notes."
        : "Connect to download your notes."
    } catch {
      loadMessage = library.syncMessage ?? "Notes couldn’t refresh. Try again shortly."
    }
  }
}

private struct NotesFeedSection: Identifiable {
  let id: String
  let title: String
  let entries: [NotesFeedEntry]
}
