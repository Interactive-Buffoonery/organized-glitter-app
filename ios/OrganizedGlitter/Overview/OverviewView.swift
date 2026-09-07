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
    let collection: String
    let recordID: String
    let filename: String?
    switch item {
    case .diamond(let project):
      collection = "projects"
      recordID = project.id
      filename = project.image?.nonEmpty
    case .page(let page):
      collection = "coloring_pages"
      recordID = page.id
      filename = page.photos.first(where: { !$0.isEmpty })
    case .book(let book):
      collection = "coloring_books"
      recordID = book.id
      filename = book.coverImage?.nonEmpty
    }
    return filename.map {
      client.fileURL(collection: collection, recordID: recordID, filename: $0)
    }
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
  case all = "All crafts"
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
      VStack(alignment: .leading, spacing: 24) {
        PageHeader("Overview")

        craftPicker

        VStack(alignment: .leading, spacing: 12) {
          SectionHeader("In progress")
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
          SectionHeader("Quick links")
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
            Label("Wishlist", systemImage: "heart")
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(QuietActionStyle())
        }
      }
      .frame(maxWidth: 760, alignment: .leading)
      .padding()
      .frame(maxWidth: .infinity)
    }
    .navigationTitle("Overview")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
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
          ForEach(items) { item in
            NavigationLink(value: item) {
              ActiveProjectRow(item: item, imageURL: model.artworkURL(for: item))
            }
            .buttonStyle(.plain)
            Divider().overlay(theme.border)
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
