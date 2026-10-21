import SwiftUI

struct StatsView: View {
  @Environment(\.theme) private var theme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var sizeClass

  let library: LibrarySession
  let verticals: VerticalPreferences

  @State private var model = StatsLoadModel()
  @State private var year = Calendar(identifier: .gregorian).component(.year, from: .now)
  @State private var refreshID = 0

  private struct LoadID: Equatable {
    let library: ObjectIdentifier
    let year: Int
    let refresh: Int
  }

  private var columns: [GridItem] {
    let count = dynamicTypeSize.isAccessibilitySize ? 1 : sizeClass == .regular ? 3 : 2
    return Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: count)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.Spacing.md) {
        if sizeClass == .regular {
          Text("Stats")
            .font(.caveat(size: 44))
            .accessibilityAddTraits(.isHeader)
        }
        if let snapshot = model.snapshot(for: library, year: year) {
          if let error = model.errorMessage {
            AccessibleErrorLabel(message: error)
            Button("Retry") { refreshID &+= 1 }
              .buttonStyle(QuietActionStyle())
          }
          if model.isStale {
            Label("Showing the last server result", systemImage: "clock")
              .font(.karla(.footnote))
          }
          if verticals.diamondPainting {
            section("Diamond art", symbol: "diamond", tiles: snapshot.diamond.tiles,
              generatedAt: snapshot.diamond.generatedAt)
          }
          if verticals.coloringBooks {
            section("Coloring", symbol: "paintpalette", tiles: snapshot.coloring.tiles,
              generatedAt: snapshot.coloring.generatedAt)
          }
          Text("Stats include synced changes. Changes waiting to sync aren’t included.")
            .font(.karla(.footnote))
            .foregroundStyle(theme.pageSecondaryForeground)
            .fixedSize(horizontal: false, vertical: true)
        } else if model.isLoading || model.errorMessage == nil {
          ProgressView("Loading stats")
            .frame(maxWidth: .infinity, minHeight: 280)
        } else {
          ContentUnavailableView {
            Label(model.needsConnection ? "Stats need a connection" : "Couldn’t load stats",
              systemImage: model.needsConnection ? "wifi.slash" : "chart.bar")
              .font(.karla(.title2).weight(.semibold))
          } description: {
            Text(model.needsConnection ? "Reconnect and try again." : model.errorMessage ?? "Connect to load your server stats.")
          } actions: {
            Button("Retry") { refreshID &+= 1 }
              .buttonStyle(QuietActionStyle())
          }
          .frame(maxWidth: .infinity, minHeight: 280)
        }
      }
      .foregroundStyle(theme.foreground)
      .padding()
      .frame(maxWidth: 900, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .background { theme.themedBackground.ignoresSafeArea() }
    .navigationTitle("Stats")
    .toolbar(removing: sizeClass == .regular ? .title : nil)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Section("Recent years") {
            Picker("Year", selection: $year) {
              ForEach(recentYears, id: \.self) { value in
                Text(String(value)).tag(value)
              }
            }
          }
        } label: {
          Label(String(year), systemImage: "calendar")
        }
        .disabled(model.needsConnection)
        .accessibilityLabel("Stats year, \(String(year))")
        .accessibilityIdentifier("stats.year")
      }
    }
    .task(id: LoadID(library: ObjectIdentifier(library), year: year, refresh: refreshID)) {
      await model.load(library: library, year: year)
    }
    .onDisappear { model.clear() }
    .refreshable { await model.load(library: library, year: year) }
  }

  private var recentYears: [Int] {
    let currentYear = min(2100, max(1900, Calendar(identifier: .gregorian).component(.year, from: .now)))
    return Array((max(1900, currentYear - 9)...currentYear).reversed())
  }

  private func section(
    _ title: String, symbol: String, tiles: [StatsTile], generatedAt: String
  ) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
      Label(title, systemImage: symbol)
        .font(.karla(.title2).weight(.semibold))
        .accessibilityAddTraits(.isHeader)
      LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.md) {
        ForEach(tiles) { tile in
          VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(tile.title)
              .font(.karla(.subheadline))
              .fixedSize(horizontal: false, vertical: true)
            Text(tile.value, format: .number)
              .font(.karla(.title).weight(.semibold))
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(Theme.Spacing.md)
          .foregroundStyle(theme.cardForeground)
          .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(tile.title)
          .accessibilityValue(tile.value.formatted())
        }
      }
      if let date = StatsGeneratedTime.date(from: generatedAt) {
        Text("Updated \(date.formatted(.relative(presentation: .numeric)))")
          .font(.karla(.footnote))
          .foregroundStyle(theme.pageSecondaryForeground)
      } else {
        Text("Update time unavailable")
          .font(.karla(.footnote))
      }
    }
  }
}
