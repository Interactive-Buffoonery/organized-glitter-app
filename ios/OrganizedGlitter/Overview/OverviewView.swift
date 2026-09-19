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

  init(client: PocketBaseClient, userID: String) {
    self.client = client
    self.userID = userID
  }

  func load() async {
    guard !isLoading else {
      return
    }

    isLoading = true
    errorMessage = nil
    defer {
      isLoading = false
      hasLoaded = true
    }

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
    } catch {
      errorMessage = error.overviewMessage
    }
  }

  func artworkURL(for item: LibraryItem) -> URL? {
    item.artworkURL(using: client)
  }

  // ponytail: month boundaries use PocketBase date strings (YYYY-MM-DD) in UTC so
  // the filter matches date_completed and completed_at field storage.
  static func startOfMonth(containing date: Date) -> String {
    monthBoundary(containing: date, monthOffset: 0)
  }

  static func startOfNextMonth(containing date: Date) -> String {
    monthBoundary(containing: date, monthOffset: 1)
  }

  private static func monthBoundary(containing date: Date, monthOffset: Int) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
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
}

struct OverviewView: View {
  @Environment(\.theme) private var theme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @State private var model: OverviewModel
  @State private var craft = OverviewCraft.all
  let verticals: VerticalPreferences
  let onWishlist: (LibrarySection) -> Void

  init(
    client: PocketBaseClient,
    userID: String,
    verticals: VerticalPreferences,
    onWishlist: @escaping (LibrarySection) -> Void
  ) {
    _model = State(initialValue: OverviewModel(client: client, userID: userID))
    self.verticals = verticals
    self.onWishlist = onWishlist
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        OverviewScreenHeader("Overview")

        craftPicker

        VStack(alignment: .leading, spacing: 6) {
          OverviewSectionHeader("In progress")
          activeWork
        }

        if model.hasLoaded, model.errorMessage == nil {
          Text(
            "Active diamond projects: \(model.activeDiamondCount) · Active coloring pages: \(model.activeColoringPageCount) · Completed this month: \(model.completedThisMonthCount)"
          )
          .font(.footnote)
          .foregroundStyle(theme.pageSecondaryForeground)
        }

        VStack(alignment: .leading, spacing: 8) {
          OverviewSectionHeader("Collection")
          Menu {
            ForEach(LibrarySection.available(for: verticals).filter { $0 != .pages }) { section in
              Button(
                section == .diamonds ? "Diamond art wishlist" : "Coloring book wishlist",
                systemImage: section.systemImage
              ) {
                onWishlist(section)
              }
            }
          } label: {
            HStack(spacing: 12) {
              Text("Wishlist")
              Spacer()
              Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.pageSecondaryForeground)
                .accessibilityHidden(true)
            }
          }
          .buttonStyle(QuietActionStyle())
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
    .navigationDestination(for: LibraryItem.self) { item in
      LibraryItemDetail(item: item, imageURL: model.artworkURL(for: item))
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
        EmptyFeatureView(
          title: craft == .all
            ? "No work in progress" : "No \(craft.rawValue.lowercased()) in progress",
          systemImage: "sparkles.rectangle.stack",
          message: "Projects and coloring pages marked in progress will appear here."
        )
        .frame(minHeight: 220)
      } else {
        LazyVStack(spacing: 0) {
          ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            NavigationLink(value: item) {
              OverviewProjectRow(item: item, imageURL: model.artworkURL(for: item))
            }
            .buttonStyle(.plain)
            if index < items.count - 1 {
              Divider()
                .overlay(theme.border)
                .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 140)
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

private struct OverviewScreenHeader: View {
  @Environment(\.theme) private var theme

  let title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    Text(title)
      .font(.largeTitle.bold())
      .foregroundStyle(theme.foreground)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityAddTraits(.isHeader)
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
      .font(.title2.weight(.semibold))
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
          if !item.subtitle.isEmpty {
            Text(item.subtitle)
              .font(.subheadline)
              .foregroundStyle(theme.pageSecondaryForeground)
          }
          StatusBadge(status: item.status, presentation: .quiet)
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

  @ViewBuilder
  private var artwork: some View {
    if dynamicTypeSize.isAccessibilitySize {
      artworkContent
        .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 220)
    } else {
      artworkContent
        .frame(width: 124, height: 124)
    }
  }

  private var artworkContent: some View {
    RecordArtwork(url: imageURL, maxHeight: 220, emptyMinHeight: 124)
      .background(theme.card, in: .rect(cornerRadius: 10))
      .clipShape(.rect(cornerRadius: 10))
      .accessibilityHidden(true)
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
