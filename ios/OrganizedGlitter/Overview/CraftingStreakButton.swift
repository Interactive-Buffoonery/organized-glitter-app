import SwiftUI

struct CraftingStreakButton: View {
  let library: LibrarySession
  let timeZone: TimeZone
  let onNotesRequest: () -> Void

  @Environment(\.theme) private var theme
  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      let entries = NotesFeed.entries(
        items: library.items, diamondNotes: library.progressNotes,
        coloringNotes: library.coloringPageProgressNotes)
      let count = CraftingStreak.count(
        noteDates: entries.map { $0.note.date }, now: context.date, timeZone: timeZone)
      pill(count: count)
    }
  }

  @ViewBuilder private func pill(count: Int) -> some View {
    if count > 0 {
      Button(action: onNotesRequest) {
        HStack(spacing: 5) {
          Image(systemName: "flame.fill")
            .foregroundStyle(theme.accent)
          Text(count, format: .number)
            .foregroundStyle(theme.foreground)
            .monospacedDigit()
        }
        .font(.karla(.body))
        .fontWeight(.semibold)
        .fixedSize()
      }
      .accessibilityLabel("\(count)-day crafting streak")
      .accessibilityHint("Opens Notes")
      .accessibilityIdentifier("home.craftingStreak")
    }
  }
}
