import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class OverviewModel {
  let client: PocketBaseClient
  let userID: String

  var activeDiamondCount = 0
  var activeColoringPageCount = 0
  var completedThisMonthCount = 0
  var items: [LibraryItem] = []
  var isLoading = false
  var hasLoaded = false
  var errorMessage: String?
  var onSessionExpired: (@MainActor @Sendable () async -> Void)?
  private var pendingReload = false

  init(client: PocketBaseClient, userID: String) {
    self.client = client
    self.userID = userID
  }

  func load() async {
    pendingReload = true
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
      await performLoad()
    }
  }

  private func performLoad() async {
    let projectOwner = PocketBaseFilter.equals(.user, userID)
    let pageOwner = PocketBaseFilter.equals(.bookUser, userID)
    let now = Date()
    let monthStart = OverviewModel.startOfMonth(containing: now)
    let monthEnd = OverviewModel.startOfNextMonth(containing: now)

    do {
      async let activeProjects: RecordList<DiamondProjectRecord> = client.list(
        collection: "projects",
        perPage: 5,
        filter: PocketBaseFilter.all([
          projectOwner,
          PocketBaseFilter.equals(.status, "progress"),
        ]),
        sort: "-updated",
        expand: "company,artist"
      )
      async let activePages: RecordList<ColoringPageRecord> = client.list(
        collection: "coloring_pages",
        perPage: 5,
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

      let (projects, pages, projectCompletions, pageCompletions) =
        try await (activeProjects, activePages, completedProjects, completedPages)

      activeDiamondCount = projects.totalItems
      activeColoringPageCount = pages.totalItems
      completedThisMonthCount = projectCompletions.totalItems + pageCompletions.totalItems
      items =
        (projects.items.map(LibraryItem.diamond)
        + pages.items.map(LibraryItem.page))
        .sorted { $0.updated > $1.updated }
    } catch APIError.cancelled {
      return
    } catch APIError.unauthenticated {
      errorMessage = APIError.unauthenticated.overviewMessage
      await onSessionExpired?()
    } catch {
      errorMessage = error.overviewMessage
    }
  }

  func artworkURL(for item: LibraryItem, token: String?) -> URL? {
    item.artworkURL(using: client, thumb: ArtworkThumb.compact, token: token)
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

enum OverviewCraft: String, CaseIterable, Identifiable {
  case all = "All"
  case diamonds = "Diamond art"
  case coloring = "Coloring"

  var id: Self { self }

  func includes(_ item: LibraryItem) -> Bool {
    switch (self, item) {
    case (.all, _), (.diamonds, .diamond), (.coloring, .page): true
    default: false
    }
  }

  func completedSections(for verticals: VerticalPreferences) -> [LibrarySection] {
    projectAndPageSections(for: verticals)
  }

  func inProgressSections(for verticals: VerticalPreferences) -> [LibrarySection] {
    projectAndPageSections(for: verticals)
  }

  func wishlistSections(for verticals: VerticalPreferences) -> [LibrarySection] {
    switch self {
    case .all:
      return LibrarySection.available(for: verticals).filter { $0 != .pages }
    case .diamonds:
      return verticals.diamondPainting ? [.diamonds] : []
    case .coloring:
      return verticals.coloringBooks ? [.books] : []
    }
  }

  func inProgressStatus(for section: LibrarySection) -> String? {
    switch section {
    case .diamonds: "progress"
    case .pages: "in_progress"
    case .books: nil
    }
  }

  private func projectAndPageSections(for verticals: VerticalPreferences) -> [LibrarySection] {
    switch self {
    case .all:
      return LibrarySection.available(for: verticals).filter { $0 != .books }
    case .diamonds:
      return verticals.diamondPainting ? [.diamonds] : []
    case .coloring:
      return verticals.coloringBooks ? [.pages] : []
    }
  }
}

struct OverviewView: View {
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.theme) private var theme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @State private var model: OverviewModel
  @State private var craft = OverviewCraft.all
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
      VStack(alignment: .leading, spacing: 18) {
        craftPicker

        VStack(alignment: .leading, spacing: 6) {
          OverviewSectionHeader("In progress")
          activeWork
        }

        VStack(alignment: .leading, spacing: 8) {
          OverviewSectionHeader("Collection")
          inProgressAction
          wishlistAction
          completedAction
        }
      }
      .frame(maxWidth: 760, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.top, 20)
      .padding(.bottom, 32)
      .frame(maxWidth: .infinity)
    }
    .background {
      theme.themedBackground.ignoresSafeArea()
    }
    .refreshable { await model.load() }
    .navigationTitle("Overview")
    .navigationDestination(for: LibraryItem.self) { item in
      LibraryItemDetailDestination(
        item: item,
        client: model.client,
        userID: model.userID,
        onCollectionChanged: { await model.load() }
      )
    }
    .task { await model.load() }
  }

  private var craftPicker: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        Picker("Craft", selection: $craft) {
          ForEach(OverviewCraft.allCases) { craft in
            Text(craft.rawValue).tag(craft)
          }
        }
        .pickerStyle(.menu)
        .buttonStyle(QuietActionStyle())
      } else {
        Picker("Craft", selection: $craft) {
          ForEach(OverviewCraft.allCases) { craft in
            Text(craft.rawValue).tag(craft)
          }
        }
        .pickerStyle(.segmented)
      }
    }
    .accessibilityIdentifier("overview.craft")
  }

  @ViewBuilder
  private var inProgressAction: some View {
    let sections = craft.inProgressSections(for: verticals)
    if sections.count == 1, let section = sections.first,
      let status = craft.inProgressStatus(for: section)
    {
      Button {
        onLibraryRequest(LibraryRequest(section: section, status: status))
      } label: {
        inProgressActionLabel
      }
      .buttonStyle(QuietActionStyle())
      .accessibilityIdentifier("overview.collection.inProgress")
    } else if !sections.isEmpty {
      Menu {
        ForEach(sections) { section in
          if let status = craft.inProgressStatus(for: section) {
            Button(
              section == .diamonds
                ? "Diamond art in progress" : "Coloring pages in progress",
              systemImage: section.systemImage
            ) {
              onLibraryRequest(LibraryRequest(section: section, status: status))
            }
          }
        }
      } label: {
        inProgressActionLabel
      }
      .buttonStyle(QuietActionStyle())
      .accessibilityIdentifier("overview.collection.inProgress")
    }
  }

  private var inProgressActionLabel: some View {
    HStack(spacing: 12) {
      Text("See all in progress")
      Spacer()
      Image(systemName: "chevron.right")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(theme.pageSecondaryForeground)
        .accessibilityHidden(true)
    }
  }

  @ViewBuilder
  private var wishlistAction: some View {
    let sections = craft.wishlistSections(for: verticals)
    if sections.count == 1, let section = sections.first {
      Button {
        onLibraryRequest(LibraryRequest(section: section, status: "wishlist"))
      } label: {
        wishlistActionLabel
      }
      .buttonStyle(QuietActionStyle())
      .accessibilityIdentifier("overview.collection.wishlist")
    } else if !sections.isEmpty {
      Menu {
        ForEach(sections) { section in
          Button(
            section == .diamonds ? "Diamond art wishlist" : "Coloring book wishlist",
            systemImage: section.systemImage
          ) {
            onLibraryRequest(LibraryRequest(section: section, status: "wishlist"))
          }
        }
      } label: {
        wishlistActionLabel
      }
      .buttonStyle(QuietActionStyle())
      .accessibilityIdentifier("overview.collection.wishlist")
    }
  }

  private var wishlistActionLabel: some View {
    HStack(spacing: 12) {
      Text("Wishlist")
      Spacer()
      Image(systemName: "chevron.right")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(theme.pageSecondaryForeground)
        .accessibilityHidden(true)
    }
  }

  @ViewBuilder
  private var completedAction: some View {
    let sections = craft.completedSections(for: verticals)
    if sections.count == 1, let section = sections.first {
      Button {
        onLibraryRequest(LibraryRequest(section: section, status: "completed"))
      } label: {
        completedActionLabel
      }
      .buttonStyle(QuietActionStyle())
      .accessibilityIdentifier("overview.collection.completed")
    } else if !sections.isEmpty {
      Menu {
        ForEach(sections) { section in
          Button(
            section == .diamonds ? "Completed diamond art" : "Completed coloring pages",
            systemImage: section.systemImage
          ) {
            onLibraryRequest(LibraryRequest(section: section, status: "completed"))
          }
        }
      } label: {
        completedActionLabel
      }
      .buttonStyle(QuietActionStyle())
      .accessibilityIdentifier("overview.collection.completed")
    }
  }

  private var completedActionLabel: some View {
    HStack(spacing: 12) {
      Text("Completed")
      Spacer()
      Image(systemName: "chevron.right")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(theme.pageSecondaryForeground)
        .accessibilityHidden(true)
    }
  }

  @ViewBuilder
  private var activeWork: some View {
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
        AccessibleErrorLabel(message: errorMessage)
        retryButton
      }
      let items = model.items.filter(craft.includes)
      if items.isEmpty {
        ContentUnavailableView(
          craft == .all
            ? "No work in progress" : "No \(craft.rawValue.lowercased()) in progress",
          systemImage: "sparkles.rectangle.stack",
          description: Text("Projects and coloring pages marked in progress will appear here.")
        )
        .frame(minHeight: 220)
      } else {
        LazyVStack(spacing: 0) {
          ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            NavigationLink(value: item) {
              OverviewProjectRow(
                item: item, imageURL: model.artworkURL(for: item, token: protectedFiles?.token))
            }
            .buttonStyle(.plain)
            if index < items.count - 1 {
              Divider()
                .overlay(theme.border)
                .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 120)
            }
          }
        }
      }
    }
  }

  private var retryButton: some View {
    Button("Try Again") {
      Task { await model.load() }
    }
    .buttonStyle(QuietActionStyle())
    .disabled(model.isLoading)
  }
}

private struct OverviewSectionHeader: View {
  @Environment(\.theme) private var theme

  let title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    Text(title)
      .font(.title3.weight(.semibold))
      .foregroundStyle(theme.foreground)
      .accessibilityAddTraits(.isHeader)
  }
}

private struct OverviewProjectRow: View {
  @Environment(\.theme) private var theme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let item: LibraryItem
  let imageURL: URL?

  var body: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 16))

    layout {
      artwork

      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(item.title)
            .font(.headline)
            .foregroundStyle(theme.foreground)
          Text(item.overviewKindLabel)
            .font(.subheadline)
            .foregroundStyle(theme.pageSecondaryForeground)
          StatusBadge(label: item.statusLabel, systemImage: item.statusSystemImage)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)

        Image(systemName: "chevron.right")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(theme.pageSecondaryForeground)
          .accessibilityHidden(true)
      }
    }
    .padding(.vertical, 7)
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
  }

  private var artwork: some View {
    CoverArtwork(
      item: item, url: imageURL,
      maxPixelDimension: dynamicTypeSize.isAccessibilitySize ? 660 : 360
    )
    .frame(width: dynamicTypeSize.isAccessibilitySize ? 176 : 84)
  }
}

private extension LibraryItem {
  var overviewKindLabel: String {
    switch self {
    case .diamond: "Diamond painting"
    case .book: "Coloring book"
    case .page: "Coloring page"
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
