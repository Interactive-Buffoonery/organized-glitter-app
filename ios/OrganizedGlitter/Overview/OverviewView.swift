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

struct OverviewView: View {
  @Environment(\.theme) private var theme

  @State private var model: OverviewModel

  init(client: PocketBaseClient, userID: String) {
    _model = State(initialValue: OverviewModel(client: client, userID: userID))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        PageHeader(
          "Overview",
          subtitle: "A quiet look at what you’re working on."
        )

        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 145, maximum: 220), spacing: 12)],
          spacing: 12
        ) {
          OverviewMetric(
            title: "Diamond projects",
            value: model.activeDiamondCount,
            systemImage: "diamond",
            surfaceIndex: 4
          )
          OverviewMetric(
            title: "Coloring pages",
            value: model.activeColoringPageCount,
            systemImage: "paintpalette",
            surfaceIndex: 2
          )
          OverviewMetric(
            title: "Completed this month",
            value: model.completedThisMonthCount,
            systemImage: "checkmark.seal",
            surfaceIndex: 1
          )
        }

        if model.isLoading, !model.hasLoaded {
          ProgressView("Loading your overview")
            .frame(maxWidth: .infinity, minHeight: 220)
        } else if let errorMessage = model.errorMessage, model.items.isEmpty {
          ContentUnavailableView {
            Label("Couldn’t load your overview", systemImage: "exclamationmark.triangle")
          } description: {
            Text(errorMessage)
          } actions: {
            Button("Try Again") {
              Task { await model.load() }
            }
            .buttonStyle(PillButtonStyle())
            .frame(maxWidth: 240)
          }
          .frame(minHeight: 280)
        } else if model.items.isEmpty {
          EmptyFeatureView(
            title: "No work in progress",
            systemImage: "sparkles.rectangle.stack",
            message: "Projects and coloring pages marked in progress will appear here."
          )
          .frame(minHeight: 280)
        } else {
          VStack(alignment: .leading, spacing: 12) {
            SectionHeader("In progress")

            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
              NavigationLink(value: item) {
                LibraryItemRow(item: item, onSurface: true)
                  .padding(12)
                  .stickerCard(index)
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
      .padding()
    }
    .navigationTitle("Overview")
    .navigationBarTitleDisplayMode(.inline)
    .background(theme.themedBackground)
    .refreshable {
      await model.load()
    }
    .navigationDestination(for: LibraryItem.self) { item in
      LibraryItemDetail(item: item)
    }
    .task {
      await model.load()
    }
  }
}

private struct OverviewMetric: View {
  @Environment(\.theme) private var theme

  let title: String
  let value: Int
  let systemImage: String
  let surfaceIndex: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Image(systemName: systemImage)
        .font(.title2)
        .foregroundStyle(theme.surfaceForeground)
        .accessibilityHidden(true)
      Text(value.formatted())
        .font(.title.bold())
        .foregroundStyle(theme.surfaceForeground)
        .contentTransition(.numericText())
      Text(title)
        .font(.subheadline)
        .foregroundStyle(theme.surfaceMutedForeground)
    }
    .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
    .padding()
    .stickerCard(surfaceIndex)
    .accessibilityElement(children: .combine)
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
