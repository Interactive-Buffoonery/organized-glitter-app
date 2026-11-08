import SwiftUI

struct CraftingStreakButton: View {
  let library: LibrarySession
  let timeZone: TimeZone
  let onNotesRequest: () -> Void

  var body: some View {
    Button(action: onNotesRequest) {
      CraftingStreakIndicator(library: library, timeZone: timeZone)
    }
    .accessibilityHint("Opens Notes.")
    .accessibilityIdentifier("home.craftingStreak")
  }
}

struct CraftingStreakIndicator: View {
  let library: LibrarySession
  let timeZone: TimeZone

  @Environment(\.theme) private var theme

  var body: some View {
    let noteDates = CraftingStreak.dateLabels(in: NotesFeed.entries(
      items: library.items, diamondNotes: library.progressNotes,
      coloringNotes: library.coloringPageProgressNotes
    ))
    TimelineView(.periodic(from: .now, by: 60)) { context in
      let count = CraftingStreak.snapshotCount(
        hasSnapshot: library.hasSnapshot, isActive: library.isActive,
        noteDates: noteDates, now: context.date, timeZone: timeZone)
      HStack(spacing: 5) {
        Image(systemName: count.map { $0 > 0 ? "flame.fill" : "flame" } ?? "ellipsis")
          .foregroundStyle(count == nil ? theme.pageSecondaryForeground : theme.accent)
        if let count, count > 0 {
          Text(count, format: .number)
            .foregroundStyle(theme.foreground)
            .monospacedDigit()
        }
      }
      .font(.karla(.body).weight(.semibold))
      .fixedSize()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(count.map {
        $0 == 0 ? "No current crafting streak" : "\($0)-day crafting streak"
      } ?? "Crafting streak unavailable")
      .accessibilityValue(library.syncMessage ?? (library.isSyncing ? "Updating downloaded library" : ""))
    }
  }
}
