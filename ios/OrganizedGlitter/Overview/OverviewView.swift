import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class OverviewModel {
  let client: PocketBaseClient
  let userID: String

  var completedThisMonthCount = 0
  /// In-progress projects and pages, most recently logged first.
  var items: [LibraryItem] = []
  /// Kitted-up projects first, then the stash.
  var upNext: [LibraryItem] = []
  /// Latest progress-note date by record id.
  var latestNoteDates: [String: String] = [:]
  var isLoading = false
  var hasLoaded = false
  var errorMessage: String?
  var onSessionExpired: (@MainActor @Sendable () async -> Void)?
  private var pendingReload = false
  private var loadGeneration = 0
  private(set) var noteDatesTask: Task<Void, Never>?

  init(client: PocketBaseClient, userID: String) {
    self.client = client
    self.userID = userID
  }

  func load() async {
    pendingReload = true
    loadGeneration &+= 1
    noteDatesTask?.cancel()
    guard !isLoading else {
      return
    }

    isLoading = true
    defer {
      isLoading = false
      hasLoaded = true
    }

    while pendingReload {
      pendingReload = false
      errorMessage = nil
      await performLoad(generation: loadGeneration)
    }
  }

  private func performLoad(generation: Int) async {
    let projectOwner = PocketBaseFilter.equals(.user, userID)
    let pageOwner = PocketBaseFilter.equals(.bookUser, userID)
    let now = Date()
    let monthStart = OverviewModel.startOfMonth(containing: now)
    let monthEnd = OverviewModel.startOfNextMonth(containing: now)

    func projects(_ status: String, perPage: Int) async throws -> RecordList<DiamondProjectRecord> {
      try await client.list(
        collection: "projects",
        perPage: perPage,
        filter: PocketBaseFilter.all([projectOwner, PocketBaseFilter.equals(.status, status)]),
        sort: "-updated",
        expand: "company,artist"
      )
    }

    do {
      async let activeProjects = projects("progress", perPage: 10)
      async let kittedProjects = projects("kitted", perPage: 10)
      async let stashProjects = projects("stash", perPage: 10)
      async let activePages: RecordList<ColoringPageRecord> = client.list(
        collection: "coloring_pages",
        perPage: 10,
        filter: PocketBaseFilter.all([
          pageOwner,
          PocketBaseFilter.equals(.status, "in_progress"),
        ]),
        sort: "-updated",
        expand: "book"
      )
      async let completedProjects: RecordList<DiamondProjectRecord> = client.list(
        collection: "projects",
        perPage: 1,
        filter: PocketBaseFilter.all([
          projectOwner,
          PocketBaseFilter.equals(.status, "completed"),
          PocketBaseFilter.greaterThanOrEqual(.dateCompleted, monthStart),
          PocketBaseFilter.lessThan(.dateCompleted, monthEnd),
        ])
      )
      async let completedPages: RecordList<ColoringPageRecord> = client.list(
        collection: "coloring_pages",
        perPage: 1,
        filter: PocketBaseFilter.all([
          pageOwner,
          PocketBaseFilter.equals(.status, "completed"),
          PocketBaseFilter.greaterThanOrEqual(.completedAt, monthStart),
          PocketBaseFilter.lessThan(.completedAt, monthEnd),
        ])
      )

      let (projects, pages, kitted, stash, projectCompletions, pageCompletions) =
        try await (
          activeProjects, activePages, kittedProjects, stashProjects, completedProjects,
          completedPages
        )

      guard !Task.isCancelled, generation == loadGeneration else { return }
      completedThisMonthCount = projectCompletions.totalItems + pageCompletions.totalItems
      latestNoteDates = [:]
      items = Self.continueOrder(
        projects.items.map(LibraryItem.diamond) + pages.items.map(LibraryItem.page),
        latestNoteDates: [:])
      upNext = (kitted.items + stash.items).map(LibraryItem.diamond)
      hasLoaded = true

      let projectIDs = projects.items.map(\.id)
      let pageIDs = pages.items.map(\.id)
      noteDatesTask = Task { [weak self] in
        guard let self else { return }
        async let diamondDates = try? self.client.latestNoteDates(
          craft: "diamond", userID: self.userID, targetIDs: projectIDs)
        async let pageDates = try? self.client.latestNoteDates(
          craft: "coloring", userID: self.userID, targetIDs: pageIDs)
        let dates = (await diamondDates ?? [:]).merging(await pageDates ?? [:]) { $1 }
        guard !Task.isCancelled, generation == self.loadGeneration else { return }
        self.latestNoteDates = dates
        self.items = Self.continueOrder(self.items, latestNoteDates: dates)
      }
    } catch APIError.cancelled {
      return
    } catch APIError.unauthenticated {
      errorMessage = APIError.unauthenticated.overviewMessage
      await onSessionExpired?()
    } catch {
      errorMessage = error.overviewMessage
    }
  }

  /// Most recently logged first; records without a note fall back to `updated`.
  /// Note dates are date-only, so a note logged today outranks today's edits.
  static func continueOrder(_ items: [LibraryItem], latestNoteDates: [String: String])
    -> [LibraryItem]
  {
    func key(_ item: LibraryItem) -> String {
      latestNoteDates[item.recordID].map { String($0.prefix(10)) + "~" } ?? item.updated
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

  func artworkURL(for item: LibraryItem, token: String?) -> URL? {
    item.artworkURL(using: client, thumb: ArtworkThumb.gallery, token: token)
  }

  // Month bounds are PocketBase date-only strings (YYYY-MM-DD) in the user's
  // calendar so "this month" matches locally encoded date_completed values.
  static func startOfMonth(containing date: Date, timeZone: TimeZone = .current) -> String {
    monthBoundary(containing: date, monthOffset: 0, timeZone: timeZone)
  }

  static func startOfNextMonth(containing date: Date, timeZone: TimeZone = .current) -> String {
    monthBoundary(containing: date, monthOffset: 1, timeZone: timeZone)
  }

  private static func monthBoundary(
    containing date: Date,
    monthOffset: Int,
    timeZone: TimeZone
  ) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = calendar.dateComponents([.year, .month], from: date)
    guard
      let monthStart = calendar.date(from: components),
      let boundary = calendar.date(byAdding: .month, value: monthOffset, to: monthStart)
    else {
      return ""
    }
    let boundaryComponents = calendar.dateComponents([.year, .month], from: boundary)
    guard let year = boundaryComponents.year, let month = boundaryComponents.month else {
      return ""
    }
    return String(format: "%04d-%02d-01", year, month)
  }
}

struct OverviewView: View {
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.theme) private var theme

  @State private var model: OverviewModel
  @State private var loggingProject: DiamondProjectRecord?
  let verticals: VerticalPreferences
  let onLibraryRequest: (LibraryRequest) -> Void

  init(
    client: PocketBaseClient,
    userID: String,
    verticals: VerticalPreferences,
    onLibraryRequest: @escaping (LibraryRequest) -> Void,
    onSessionExpired: @escaping @MainActor @Sendable () async -> Void = {}
  ) {
    let model = OverviewModel(client: client, userID: userID)
    model.onSessionExpired = onSessionExpired
    _model = State(initialValue: model)
    self.verticals = verticals
    self.onLibraryRequest = onLibraryRequest
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        VStack(alignment: .leading, spacing: 12) {
          shortcutHeader(
            "Continue", id: "overview.continue",
            requests: inProgressRequests)
          continueContent
        }

        if model.hasLoaded, !upNext.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            shortcutHeader(
              "Up next from your stash", id: "overview.upNext",
              requests: [
                ("Kitted up", LibraryRequest(section: .diamonds, status: "kitted")),
                ("In stash", LibraryRequest(section: .diamonds, status: "stash")),
              ])
            upNextShelf
          }
        }

        if model.hasLoaded, !completedRequests.isEmpty {
          finishedThisMonth
        }
      }
      .frame(maxWidth: 760, alignment: .leading)
      .padding(.top, 12)
      .padding(.bottom, 32)
      .frame(maxWidth: .infinity)
    }
    .background {
      theme.themedBackground.ignoresSafeArea()
    }
    .refreshable { await model.load() }
    .navigationTitle("Home")
    .navigationDestination(for: LibraryItem.self) { item in
      LibraryItemDetailDestination(
        item: item,
        client: model.client,
        userID: model.userID,
        onCollectionChanged: { await model.load() }
      )
    }
    .sheet(item: $loggingProject) { project in
      DiamondProgressNoteEditor(
        model: LibraryItemDetailModel(
          item: .diamond(project), client: model.client, userID: model.userID),
        onCollectionChanged: { await model.load() }
      )
    }
    .task { await model.load() }
  }

  private var continueItems: [LibraryItem] {
    model.items.filter { item in
      switch item {
      case .diamond: verticals.diamondPainting
      case .book, .page: verticals.coloringBooks
      }
    }
  }

  private var upNext: [LibraryItem] {
    verticals.diamondPainting ? model.upNext : []
  }

  private var inProgressRequests: [(String, LibraryRequest)] {
    var requests: [(String, LibraryRequest)] = []
    if verticals.diamondPainting {
      requests.append(("Diamond art in progress", LibraryRequest(section: .diamonds, status: "progress")))
    }
    if verticals.coloringBooks {
      requests.append(("Coloring pages in progress", LibraryRequest(section: .pages, status: "in_progress")))
    }
    return requests
  }

  private var completedRequests: [(String, LibraryRequest)] {
    var requests: [(String, LibraryRequest)] = []
    if verticals.diamondPainting {
      requests.append(("Completed diamond art", LibraryRequest(section: .diamonds, status: "completed")))
    }
    if verticals.coloringBooks {
      requests.append(("Completed coloring pages", LibraryRequest(section: .pages, status: "completed")))
    }
    return requests
  }

  /// A section title that opens Library, or a menu when several crafts apply.
  @ViewBuilder
  private func shortcutHeader(
    _ title: String, id: String, requests: [(String, LibraryRequest)]
  ) -> some View {
    let label = HStack(spacing: 6) {
      Text(title)
        .font(.title3.weight(.semibold))
        .foregroundStyle(theme.foreground)
        .multilineTextAlignment(.leading)
      Image(systemName: "chevron.right")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(theme.primary)
        .accessibilityHidden(true)
    }
    Group {
      if requests.count == 1, let request = requests.first?.1 {
        Button { onLibraryRequest(request) } label: { label }
      } else if !requests.isEmpty {
        Menu {
          ForEach(requests, id: \.0) { title, request in
            Button(title) { onLibraryRequest(request) }
          }
        } label: {
          label
        }
      } else {
        label
      }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(.isHeader)
    .accessibilityIdentifier(id)
    .padding(.horizontal, 20)
  }

  @ViewBuilder
  private var continueContent: some View {
    if model.isLoading, !model.hasLoaded {
      ProgressView("Loading your overview")
        .frame(maxWidth: .infinity, minHeight: 220)
    } else if let errorMessage = model.errorMessage, model.items.isEmpty {
      ContentUnavailableView {
        Label("Couldn’t load your overview", systemImage: "exclamationmark.triangle")
      } description: {
        Text(errorMessage)
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
        .padding(.horizontal, 20)
      }
      if continueItems.isEmpty {
        ContentUnavailableView(
          "No work in progress",
          systemImage: "sparkles.rectangle.stack",
          description: Text("Projects and coloring pages marked in progress will appear here.")
        )
        .frame(minHeight: 220)
      } else {
        ScrollView(.horizontal) {
          LazyHStack(alignment: .top, spacing: 14) {
            ForEach(continueItems) { item in
              ContinueCard(
                item: item,
                imageURL: model.artworkURL(for: item, token: protectedFiles?.token),
                caption: model.latestNoteDates[item.recordID]
                  .flatMap { OverviewModel.loggedCaption(noteDate: $0) },
                onLog: logAction(for: item)
              )
            }
          }
          .scrollTargetLayout()
          .padding(.horizontal, 20)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("overview.continue.shelf")
      }
    }
  }

  // ponytail: pages have no Log sheet yet, so their cover opens the detail.
  private func logAction(for item: LibraryItem) -> (() -> Void)? {
    guard case .diamond(let project) = item else { return nil }
    return { loggingProject = project }
  }

  private var upNextShelf: some View {
    ScrollView(.horizontal) {
      LazyHStack(alignment: .top, spacing: 12) {
        ForEach(upNext) { item in
          NavigationLink(value: item) {
            UpNextCover(
              item: item,
              imageURL: model.artworkURL(for: item, token: protectedFiles?.token))
          }
          .buttonStyle(.plain)
        }
      }
      .scrollTargetLayout()
      .padding(.horizontal, 20)
    }
    .scrollTargetBehavior(.viewAligned)
    .scrollIndicators(.hidden)
    .accessibilityIdentifier("overview.upNext.shelf")
  }

  @ViewBuilder
  private var finishedThisMonth: some View {
    let count = model.completedThisMonthCount
    let label = HStack(spacing: 12) {
      Image(systemName: "checkmark.seal.fill")
        .font(.title3)
        .foregroundStyle(theme.accent)
        .accessibilityHidden(true)
      Text(count == 0 ? "Nothing finished yet this month" : "\(count) finished this month")
        .font(.body.weight(.medium))
        .foregroundStyle(theme.foreground)
        .multilineTextAlignment(.leading)
      Spacer(minLength: 0)
      Image(systemName: "chevron.right")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(theme.pageSecondaryForeground)
        .accessibilityHidden(true)
    }
    .padding(16)
    .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
    .contentShape(.rect)

    Group {
      if completedRequests.count == 1, let request = completedRequests.first?.1 {
        Button { onLibraryRequest(request) } label: { label }
      } else {
        Menu {
          ForEach(completedRequests, id: \.0) { title, request in
            Button(title) { onLibraryRequest(request) }
          }
        } label: {
          label
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("overview.finished")
    .padding(.horizontal, 20)
  }

  private var retryButton: some View {
    Button("Try Again") {
      Task { await model.load() }
    }
    .buttonStyle(QuietActionStyle())
    .disabled(model.isLoading)
  }
}

private struct ContinueCard: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.theme) private var theme
  @ScaledMetric(relativeTo: .body) private var width = 156

  let item: LibraryItem
  let imageURL: URL?
  let caption: String?
  let onLog: (() -> Void)?

  var body: some View {
    let cardWidth = min(width * (horizontalSizeClass == .regular ? 1.3 : 1), 300)
    VStack(alignment: .leading, spacing: 8) {
      NavigationLink(value: item) {
        VStack(alignment: .leading, spacing: 6) {
          CoverArtwork(item: item, url: imageURL, maxPixelDimension: 660)
            .frame(width: cardWidth, height: cardWidth * 5 / 4)
          Text(item.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(theme.foreground)
            .lineLimit(2, reservesSpace: true)
          Label(caption ?? item.statusLabel, systemImage: item.statusSystemImage)
            .font(.caption)
            .foregroundStyle(theme.pageSecondaryForeground)
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .combine)
    }
    .frame(width: cardWidth)
    .overlay(alignment: .topTrailing) {
      if let onLog {
        Button("Log", systemImage: "pencil", action: onLog)
          .font(.footnote.weight(.semibold))
          .glassButton()
          .padding(8)
          .frame(width: cardWidth, height: cardWidth * 5 / 4, alignment: .bottomTrailing)
          .accessibilityLabel("Log progress for \(item.title)")
          .accessibilityIdentifier("overview.log.\(item.recordID)")
      }
    }
  }
}

private struct UpNextCover: View {
  @ScaledMetric(relativeTo: .body) private var width = 104

  let item: LibraryItem
  let imageURL: URL?

  var body: some View {
    CoverArtwork(item: item, url: imageURL, maxPixelDimension: 360)
      .frame(width: min(width, 220))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(item.title), \(item.statusLabel)")
      .accessibilityAddTraits(.isButton)
  }
}

extension View {
  /// Liquid Glass on iOS 26, a material capsule before it.
  @ViewBuilder
  func glassButton() -> some View {
    if #available(iOS 26, *) {
      buttonStyle(.glass)
    } else {
      buttonStyle(.bordered)
        .background(.ultraThinMaterial, in: .capsule)
    }
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
