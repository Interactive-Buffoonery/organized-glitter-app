import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class OverviewModel {
  let library: LibrarySession
  var userID: String { library.userID }

  /// In-progress projects and pages, most recently logged first.
  var items: [LibraryItem] = []
  /// Latest progress-note date and text by record id.
  var latestNoteDates: [String: String] = [:]
  var latestNoteTexts: [String: String] = [:]
  /// Total pages by coloring book id.
  var bookPageCounts: [String: Int] = [:]
  var isLoading = false
  var hasLoaded = false
  var errorMessage: String?
  var onSessionExpired: (@MainActor @Sendable () async -> Void)?
  init(library: LibrarySession) {
    self.library = library
  }

  func load(animation: Animation? = nil) async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      try await library.loadLocal()
      let projects = library.items.compactMap { item -> DiamondProjectRecord? in
        if case .diamond(let project) = item, project.user == userID { return project }
        return nil
      }
      let pages = library.items.compactMap { item -> ColoringPageRecord? in
        if case .page(let page) = item { return page }
        return nil
      }
      var pageCounts: [String: Int] = [:]
      for case .book(let book) in library.items { pageCounts[book.id] = book.totalPages }
      let projectIDs = Set(projects.map(\.id))
      let pageIDs = Set(pages.map(\.id))
      var latest: [String: (date: String, created: String, content: String)] = [:]
      func keep(_ id: String, date: String, created: String, content: String) {
        if let current = latest[id], (current.date, current.created) >= (date, created) { return }
        latest[id] = (date, created, content)
      }
      for note in library.progressNotes where projectIDs.contains(note.project) {
        keep(note.project, date: note.date, created: note.created, content: note.content)
      }
      for note in library.coloringPageProgressNotes where pageIDs.contains(note.page) {
        keep(note.page, date: note.date, created: note.created, content: note.content)
      }
      let dates = latest.mapValues(\.date)
      let created = latest.mapValues(\.created)
      let active =
        projects.filter { $0.status == "progress" }.map(LibraryItem.diamond)
        + pages.filter { $0.status == "in_progress" }.map(LibraryItem.page)
      // Up to ten of each craft, so hiding either one never empties Home.
      var perCraft: [LibrarySection: Int] = [:]
      let ordered = Self.continueOrder(active, latestNoteDates: dates, noteCreated: created)
        .filter { item in
          perCraft[item.section, default: 0] += 1
          return perCraft[item.section, default: 0] <= 10
        }
      bookPageCounts = pageCounts
      latestNoteTexts = latest.mapValues(\.content)
      withAnimation(animation) {
        latestNoteDates = dates
        items = ordered
      }
      hasLoaded = true
    } catch APIError.unauthenticated {
      errorMessage = APIError.unauthenticated.overviewMessage
      await onSessionExpired?()
    } catch {
      errorMessage = error.overviewMessage
    }
  }

  func refresh() async {
    do { try await library.refresh() } catch { errorMessage = error.overviewMessage }
    await load()
  }

  /// Most recently logged first, then most recently started; records with
  /// neither fall back to `updated`. Note dates are date-only, so a note
  /// logged today outranks a start or an edit today, and same-day notes
  /// compare by when they were created.
  static func continueOrder(
    _ items: [LibraryItem], latestNoteDates: [String: String], noteCreated: [String: String]
  ) -> [LibraryItem] {
    func key(_ item: LibraryItem) -> String {
      if let note = latestNoteDates[item.recordID] {
        return String(note.prefix(10)) + "~" + (noteCreated[item.recordID] ?? "")
      }
      let started: String? =
        switch item {
        case .diamond(let project): project.dateStarted
        case .page(let page): page.startedAt
        case .book: nil
        }
      return started?.nonEmpty.map { String($0.prefix(10)) } ?? item.updated
    }
    return items.sorted { key($0) > key($1) }
  }

  /// "Logged today", "Logged yesterday", "Logged 3 days ago", then a date.
  static func loggedCaption(
    noteDate: String, now: Date = Date(), timeZone: TimeZone = .current
  ) -> String? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let parser = DateFormatter()
    parser.calendar = calendar
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.timeZone = timeZone
    parser.dateFormat = "yyyy-MM-dd"
    guard let date = parser.date(from: String(noteDate.prefix(10))),
      let days = calendar.dateComponents(
        [.day], from: date, to: calendar.startOfDay(for: now)
      ).day
    else { return nil }
    switch days {
    case ...0: return "Logged today"
    case 1: return "Logged yesterday"
    case 2..<7: return "Logged \(days) days ago"
    default: return DetailDateOnly.formatted(noteDate, timeZone: timeZone).map { "Logged \($0)" }
    }
  }
}

struct OverviewView: View {
  @Environment(FormDrawer.self) private var formDrawer
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.theme) private var theme

  @State private var model: OverviewModel
  @Binding private var logEditor: LibraryItemDetailModel?
  let loggedItemID: LibraryItem.ID?
  let refreshGeneration: Int
  let verticals: VerticalPreferences
  let onLibraryRequest: (LibraryRequest) -> Void
  let onNotesRequest: () -> Void

  init(
    library: LibrarySession,
    verticals: VerticalPreferences,
    logEditor: Binding<LibraryItemDetailModel?>,
    loggedItemID: LibraryItem.ID?,
    refreshGeneration: Int,
    onLibraryRequest: @escaping (LibraryRequest) -> Void,
    onNotesRequest: @escaping () -> Void,
    onSessionExpired: @escaping @MainActor @Sendable () async -> Void = {}
  ) {
    let model = OverviewModel(library: library)
    model.onSessionExpired = onSessionExpired
    _model = State(initialValue: model)
    _logEditor = logEditor
    self.loggedItemID = loggedItemID
    self.refreshGeneration = refreshGeneration
    self.verticals = verticals
    self.onLibraryRequest = onLibraryRequest
    self.onNotesRequest = onNotesRequest
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        greeting
        content
      }
      .padding(.horizontal, 20)
      .frame(maxWidth: 760, alignment: .leading)
      .padding(.top, 8)
      .padding(.bottom, 32)
      .frame(maxWidth: .infinity)
    }
    .background {
      theme.themedBackground.ignoresSafeArea()
    }
    .refreshable { await model.refresh() }
    // The greeting is the visible title: iPadOS 26 hides a tab root's bar
    // title, so "Home" only names the back button.
    .navigationTitle("Home")
    .toolbarTitleDisplayMode(.inline)
    .toolbar(removing: .title)
    .navigationDestination(for: LibraryItem.self) { item in
      LibraryItemDetailDestination(
        item: item,
        library: model.library,
        logEditor: $logEditor,
        onCollectionChanged: { await model.load() },
        onEditPageCount: { book in
          formDrawer.presentPageCountEditor(book: book, library: model.library)
        }
      )
      .environment(formDrawer)
    }
    .task(id: model.library.generation) { await model.load() }
    .onChange(of: refreshGeneration) { _, _ in Task { await model.load() } }
    .onChange(of: loggedItemID) { _, id in
      guard id != nil else { return }
      // The confirmed item becomes the hero once the drawer closes.
      Task { await model.load(animation: reduceMotion ? nil : Theme.motion) }
    }
  }

  private var greeting: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
        .textCase(.uppercase)
        .font(.karla(.caption).weight(.semibold))
        .tracking(0.8)
        .foregroundStyle(theme.pageSecondaryForeground)
      Text("Welcome back")
        .font(.caveat(size: 40))
        .foregroundStyle(theme.foreground)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("overview.heading")
    }
  }

  private var visibleItems: [LibraryItem] {
    model.items.filter { item in
      switch item {
      case .diamond: verticals.diamondPainting
      case .book, .page: verticals.coloringBooks
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    if !model.library.hasSnapshot, model.library.syncMessage == nil,
      model.errorMessage == nil
    {
      ProgressView("Loading your overview")
        .frame(maxWidth: .infinity, minHeight: 220)
    } else if !model.library.hasSnapshot || (model.errorMessage != nil && model.items.isEmpty) {
      ContentUnavailableView {
        Label("Couldn’t load your overview", systemImage: "exclamationmark.triangle")
      } description: {
        Text(model.errorMessage ?? model.library.syncMessage ?? "Connect to download your library.")
      } actions: {
        retryButton
      }
      .frame(minHeight: 280)
    } else {
      if let errorMessage = model.errorMessage {
        VStack(alignment: .leading, spacing: 8) {
          AccessibleErrorLabel(message: errorMessage)
          retryButton
        }
      }
      let items = visibleItems
      if let hero = items.first {
        let others = items.dropFirst()
        heroCard(hero)
        pickUpSection(
          "Diamond art", id: "diamonds",
          others.filter { $0.section == .diamonds })
        pickUpSection(
          "Coloring", id: "coloring",
          others.filter { $0.section == .pages })
      } else if model.hasLoaded {
        emptyState
      }
    }
  }

  private func heroCard(_ item: LibraryItem) -> some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
    return VStack(alignment: .leading, spacing: 14) {
      NavigationLink(value: item) {
        layout {
          CoverArtwork(
            item: item,
            url: protectedFiles?.artworkURL(for: item, thumb: ArtworkThumb.gallery),
            maxPixelDimension: 480
          )
          .frame(width: 128, height: 160)
          VStack(alignment: .leading, spacing: 4) {
            Text("Last worked on")
              .textCase(.uppercase)
              .font(.karla(.caption).weight(.bold))
              .tracking(0.8)
              .foregroundStyle(theme.accent)
            Text(item.title)
              .font(.karla(.title3).weight(.semibold))
              .foregroundStyle(theme.cardForeground)
            ForEach(heroDetails(item), id: \.self) { line in
              Text(line)
            }
            .font(.karla(.subheadline))
            .foregroundStyle(theme.mutedForeground)
            if let note = heroNote(item) {
              Text(note)
                .font(.karla(.footnote).italic())
                .foregroundStyle(theme.mutedForeground)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 6 : 2)
            }
          }
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("overview.hero")

      if let log = logAction(for: item) {
        Button(action: log) {
          Label("Log progress", systemImage: "pencil")
            .font(.karla(.body).weight(.semibold))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(theme.primary)
        .foregroundStyle(theme.primaryForeground)
        .disabledWhileFormPresented(formDrawer)
        .accessibilityLabel("Log progress for \(item.title)")
        .accessibilityIdentifier("overview.log.\(item.recordID)")
      }
    }
    .padding(14)
    .background(theme.card, in: .rect(cornerRadius: 20))
  }

  /// Artist then size and drill for kits; "Book · page N of M" for pages.
  private func heroDetails(_ item: LibraryItem) -> [String] {
    switch item {
    case .diamond(let project):
      let maker = project.expand?.artist?.name.nonEmpty ?? project.expand?.company?.name.nonEmpty
      let specifications = LibraryItemMetadata(item: item).specifications.nonEmpty
      return [maker, specifications].compactMap { $0 }
    case .page(let page):
      return [bookAndPage(page, withTotal: true)]
    case .book:
      return []
    }
  }

  /// "Princesses · page 4", or "Princesses · page 4 of 30" with the book's total.
  private func bookAndPage(_ page: ColoringPageRecord, withTotal: Bool = false) -> String {
    let total = withTotal ? model.bookPageCounts[page.book].map { " of \($0)" } ?? "" : ""
    return [page.expand?.book?.title.nonEmpty, "page \(page.pageNumber)\(total)"]
      .compactMap { $0 }.joined(separator: " · ")
  }

  private func heroNote(_ item: LibraryItem) -> AttributedString? {
    let caption = loggedCaption(item)
    guard
      let note = model.latestNoteTexts[item.recordID]?
        .trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    else { return caption.map { AttributedString($0) } }
    var text = AttributedString("“")
    text += (try? AttributedString(
      markdown: note, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(note)
    text += AttributedString("”")
    if let caption { text += AttributedString(" · \(caption)") }
    return text
  }

  private func loggedCaption(_ item: LibraryItem) -> String? {
    model.latestNoteDates[item.recordID].flatMap { OverviewModel.loggedCaption(noteDate: $0) }
  }

  @ViewBuilder
  private func pickUpSection(_ craft: String, id: String, _ items: [LibraryItem]) -> some View {
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        Text("Also in progress · \(craft)")
          .textCase(.uppercase)
          .font(.karla(.caption).weight(.bold))
          .tracking(0.8)
          .foregroundStyle(theme.pageSecondaryForeground)
          .accessibilityAddTraits(.isHeader)
        VStack(spacing: 0) {
          ForEach(items) { item in
            if item.id != items.first?.id {
              Divider().padding(.leading, 58)
            }
            row(item)
          }
        }
        .background(theme.card, in: .rect(cornerRadius: 16))
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("overview.\(id)")
    }
  }

  private func row(_ item: LibraryItem) -> some View {
    HStack(spacing: 12) {
      NavigationLink(value: item) {
        HStack(spacing: 12) {
          CoverArtwork(
            item: item,
            url: protectedFiles?.artworkURL(for: item, thumb: ArtworkThumb.gallery),
            maxPixelDimension: 120
          )
          .frame(width: 34, height: 42.5)
          VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
              .font(.karla(.subheadline).weight(.semibold))
              .foregroundStyle(theme.cardForeground)
            Text(rowDetail(item))
              .font(.karla(.caption))
              .foregroundStyle(theme.mutedForeground)
          }
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .combine)

      if let log = logAction(for: item) {
        Button("Log progress for \(item.title)", systemImage: "pencil", action: log)
          .labelStyle(.iconOnly)
          .font(.karla(.footnote).weight(.semibold))
          .buttonStyle(.bordered)
          .buttonBorderShape(.circle)
          .tint(theme.primary)
          .disabledWhileFormPresented(formDrawer)
          .accessibilityIdentifier("overview.log.\(item.recordID)")
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }

  /// "40×50 · Square · Logged 2 days ago"; "Book · page 4 · Logged Sep 12".
  private func rowDetail(_ item: LibraryItem) -> String {
    let parts: [String?] =
      switch item {
      case .diamond(let project):
        [
          LibraryItemMetadata(item: item).specifications.nonEmpty,
          loggedCaption(item)
            ?? project.dateStarted.flatMap { DetailDateOnly.formatted($0) }.map { "Started \($0)" },
        ]
      case .page(let page):
        [bookAndPage(page), loggedCaption(item)]
      case .book:
        []
      }
    return parts.compactMap { $0 }.joined(separator: " · ")
  }

  /// Opens the stash shelf for the first enabled craft.
  private var stashRequest: LibraryRequest? {
    if verticals.diamondPainting { return LibraryRequest(section: .diamonds, status: "stash") }
    if verticals.coloringBooks { return LibraryRequest(section: .books, status: "in_stash") }
    return nil
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label("Nothing in progress", systemImage: "sparkles")
    } description: {
      Text("Pick something from your stash to start. It will wait for you here.")
    } actions: {
      if let request = stashRequest {
        Button("Browse your stash") { onLibraryRequest(request) }
          .buttonStyle(.borderedProminent)
          .tint(theme.primary)
          .foregroundStyle(theme.primaryForeground)
          .accessibilityIdentifier("overview.stash")
      }
    }
    .frame(maxWidth: .infinity, minHeight: 280)
  }

  private func logAction(for item: LibraryItem) -> (() -> Void)? {
    switch item {
    case .diamond, .page:
      return { logEditor = LibraryItemDetailModel(item: item, library: model.library) }
    case .book:
      return nil
    }
  }

  private var retryButton: some View {
    Button("Try Again") {
      Task { await model.refresh() }
    }
    .buttonStyle(QuietActionStyle())
    .disabled(model.isLoading || model.library.isSyncing)
    .accessibilityIdentifier("overview.retry")
  }
}

extension Error {
  fileprivate var overviewMessage: String {
    switch self as? APIError {
    case .offline:
      "You’re offline. Your last in-memory overview remains visible."
    case .forbidden:
      "Your account does not have permission to load this overview."
    case .unauthenticated:
      "Your session has expired. Sign in again."
    default:
      "Your overview is unavailable right now. Try again shortly."
    }
  }
}
