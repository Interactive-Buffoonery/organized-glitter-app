import SwiftUI

@MainActor
@Observable
final class NotesFilterModel {
  private let library: LibrarySession
  private(set) var craft: NotesCraft = .all
  private(set) var source: NotesSourceID?
  private(set) var year: Int?

  init(library: LibrarySession) {
    self.library = library
  }

  func selectCraft(_ craft: NotesCraft) {
    guard self.craft != craft else { return }
    self.craft = craft
    source = nil
    year = nil
    library.captureAnalytics(.notesCraftFilterChanged, properties: ["craft": craft.rawValue])
  }

  func selectYear(_ year: Int?) {
    guard self.year != year else { return }
    self.year = year
    library.captureAnalytics(.notesYearFilterChanged, properties: ["filter_active": year != nil])
  }

  func selectSource(_ source: NotesSourceID?) {
    guard self.source != source else { return }
    self.source = source
    let sourceKind = switch source {
    case .project: "project"
    case .book: "book"
    case nil: "all"
    }
    library.captureAnalytics(.notesSourceFilterChanged, properties: [
      "source_kind": sourceKind, "craft": craft.rawValue,
    ])
  }

  func align(to verticals: VerticalPreferences) {
    let selected = craft.resolved(for: verticals) ?? .all
    if selected != craft {
      craft = selected
      source = nil
      year = nil
    }
  }

  func reconcile(availableSources: [NotesSource], availableYears: [Int]) {
    let resolved = NotesFeed.resolvedSource(source, in: availableSources)
    if resolved != source { source = resolved }
    if let year, !availableYears.contains(year) { self.year = nil }
  }

  func reset() {
    source = nil
    year = nil
  }
}

/// Notes from every enabled craft, grouped by the date the maker chose.
struct NotesFeedView: View {
  @Environment(FormDrawer.self) private var formDrawer
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.locale) private var locale
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.theme) private var theme
  @Environment(\.timeZone) private var timeZone

  let library: LibrarySession
  let verticals: VerticalPreferences
  let onAddNote: () -> Void

  @State private var filters: NotesFilterModel
  @State private var sources: [NotesSource] = []
  @State private var loadMessage: String?
  @State private var allEntries: [NotesFeedEntry] = []
  @State private var sections: [NotesFeedSection] = []
  @State private var years: [Int] = []
  @State private var photos: [DetailPhoto] = []

  init(
    library: LibrarySession, verticals: VerticalPreferences, onAddNote: @escaping () -> Void
  ) {
    self.library = library
    self.verticals = verticals
    self.onAddNote = onAddNote
    _filters = State(initialValue: NotesFilterModel(library: library))
  }

  var body: some View {
    let availableCrafts = NotesCraft.available(for: verticals)
    let visibleCraft = filters.craft.resolved(for: verticals)

    ScrollView {
      LazyVStack(alignment: .leading, spacing: 20) {
        if sizeClass == .regular {
          Text("Notes")
            .font(.caveat(size: 34))
            .foregroundStyle(theme.foreground)
            .accessibilityAddTraits(.isHeader)
        }

        if availableCrafts.count > 1 {
          if dynamicTypeSize.isAccessibilitySize {
            craftPicker(availableCrafts)
              .pickerStyle(.menu)
          } else {
            craftPicker(availableCrafts)
              .pickerStyle(.segmented)
          }
        }

        if library.hasSnapshot, !sources.isEmpty {
          sourcePicker
          if let selectedSource {
            ViewThatFits(in: .horizontal) {
              HStack(alignment: .firstTextBaseline, spacing: 12) {
                sourceSummary(selectedSource)
                Spacer(minLength: 0)
                clearSourceButton
              }
              VStack(alignment: .leading, spacing: 8) {
                sourceSummary(selectedSource)
                clearSourceButton
              }
            }
          }
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
              VStack(alignment: .leading, spacing: 20) {
                Text(month.title)
                  .font(.karla(.title3).weight(.semibold))
                  .foregroundStyle(theme.foreground)
                  .accessibilityAddTraits(.isHeader)
                  .padding(.top, 8)

                ForEach(month.entries) { entry in
                  VStack(alignment: .leading, spacing: 8) {
                    NavigationLink(value: entry.target) {
                      HStack(alignment: .top, spacing: 10) {
                        if !dynamicTypeSize.isAccessibilitySize {
                          Image(systemName: entry.craft == .diamond
                            ? LibrarySection.diamonds.systemImage : LibrarySection.pages.systemImage)
                            .font(.karla(.subheadline).weight(.medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(theme.primary)
                            .frame(width: 32, height: 32)
                            .background(theme.primary.opacity(0.10), in: .rect(cornerRadius: 8))
                            .accessibilityHidden(true)
                        }
                        Text(entry.contextTitle)
                          .font(.karla(.subheadline).weight(.semibold))
                          .foregroundStyle(theme.foreground)
                          .multilineTextAlignment(.leading)
                          .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if !dynamicTypeSize.isAccessibilitySize {
                          Image(systemName: "chevron.right")
                            .font(.karla(.caption).weight(.semibold))
                            .foregroundStyle(theme.pageSecondaryForeground)
                            .accessibilityHidden(true)
                        }
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
    .photoViewer(photos, library: library, surface: .notesFeed)
    .background { theme.themedBackground.ignoresSafeArea() }
    .refreshable { await refresh() }
    .navigationTitle("Notes")
    .navigationBarTitleDisplayMode(sizeClass == .regular ? .inline : .large)
    .accessibilityIdentifier("notes.feed")
    .toolbar {
      if years.count > 1 {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Picker("Year", selection: Binding(
              get: { filters.year }, set: { filters.selectYear($0) }
            )) {
              Text("All years").tag(Int?.none)
              ForEach(years, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
            }
          } label: {
            Label(filters.year.map(String.init) ?? "All years", systemImage: "calendar")
          }
          .accessibilityLabel("Filter notes by year")
          .accessibilityValue(filters.year.map(String.init) ?? "All years")
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
    .onChange(of: filters.craft) { _, _ in updateVisible() }
    .onChange(of: filters.source) { _, _ in updateVisible() }
    .onChange(of: filters.year) { _, _ in updateVisible() }
    .onChange(of: verticals) { _, _ in
      filters.align(to: verticals)
      updateVisible()
    }
    .onChange(of: protectedFiles?.token) { _, _ in updatePhotos() }
    .onChange(of: locale) { _, _ in updateVisible() }
    .onChange(of: timeZone) { _, _ in updatePhotos() }
    .onChange(of: library.scope) { _, _ in
      filters.reset()
      allEntries = []
      sources = []
      sections = []
      photos = []
    }
    .task(id: NotesFeedLoadID(scope: library.scope, generation: library.generation)) {
      do {
        try await library.loadLocal()
        try Task.checkCancellation()
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

  private var selectedSource: NotesSource? {
    sources.first { $0.id == filters.source }
  }

  private var sourcePicker: some View {
    Menu {
      Picker("Source", selection: Binding(
        get: { filters.source }, set: { filters.selectSource($0) }
      )) {
        Text("All projects and books").tag(NotesSourceID?.none)
        ForEach(sources) { option in
          Text(option.title).tag(NotesSourceID?.some(option.id))
        }
      }
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("Source: \(selectedSource?.title ?? "All projects and books")")
          .fixedSize(horizontal: false, vertical: true)
          .multilineTextAlignment(.leading)
        Image(systemName: "chevron.down")
          .accessibilityHidden(true)
      }
      .font(.karla(.body))
      .frame(minHeight: 44, alignment: .leading)
    }
    .tint(theme.primary)
    .accessibilityLabel("Filter notes by project or book")
    .accessibilityValue(selectedSource?.title ?? "All projects and books")
    .accessibilityIdentifier("notes.source")
  }

  private func sourceSummary(_ selected: NotesSource) -> some View {
    Text("Showing notes for \(selected.title)")
      .font(.karla(.subheadline))
      .foregroundStyle(theme.pageSecondaryForeground)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("notes.source.summary")
  }

  private var clearSourceButton: some View {
    Button("Clear") { filters.selectSource(nil) }
      .font(.karla(.subheadline))
      .frame(minHeight: 44)
      .tint(theme.primary)
      .accessibilityLabel("Clear source filter")
      .accessibilityIdentifier("notes.source.clear")
  }

  private func craftPicker(_ crafts: [NotesCraft]) -> some View {
    Picker("Craft", selection: Binding(
      get: { filters.craft }, set: { filters.selectCraft($0) }
    )) {
      ForEach(crafts) { Text($0.title).tag($0) }
    }
    .accessibilityLabel("Filter notes by craft")
    .accessibilityIdentifier("notes.craft")
  }

  private func updateVisible() {
    let craftEntries = NotesFeed.filter(
      allEntries, craft: filters.craft, year: nil, verticals: verticals)
    let availableSources = NotesFeed.sources(in: craftEntries, items: library.items)
    sources = availableSources
    let availableYears = NotesFeed.years(in: craftEntries)
    years = availableYears
    filters.reconcile(availableSources: availableSources, availableYears: availableYears)
    let visibleEntries = NotesFeed.filter(
      craftEntries, craft: filters.craft, year: filters.year, verticals: verticals,
      source: filters.source)
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
      if let selectedSource {
        Label("No notes for \(selectedSource.title)", systemImage: "note.text")
      } else if filters.year != nil {
        Label("No notes this year", systemImage: "note.text")
      } else {
        Label("Start logging progress", systemImage: "note.text")
      }
    } description: {
      Text(filters.year.map { "No notes in \($0)." } ?? description)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("notes.empty")
    } actions: {
      if filters.source != nil || filters.year != nil {
        Button("Show all notes") { filters.reset() }
          .buttonStyle(.borderedProminent)
          .tint(theme.primary)
          .accessibilityIdentifier("notes.filters.clear")
      } else if !NotesCraft.available(for: verticals).isEmpty {
        Button("Add a progress note", action: onAddNote)
          .disabledWhileFormPresented(formDrawer)
          .buttonStyle(.borderedProminent)
          .tint(theme.primary)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 360)
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

private struct NotesFeedLoadID: Hashable {
  let scope: LocalAccountScope
  let generation: Int
}
