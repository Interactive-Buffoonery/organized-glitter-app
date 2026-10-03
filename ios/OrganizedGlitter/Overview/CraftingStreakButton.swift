import SwiftUI

struct CraftingStreakButton: View {
  let library: LibrarySession
  let timeZone: TimeZone
  let onNotesRequest: () -> Void

  @Environment(\.theme) private var theme
  @State private var count = 0

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      pill
        .task(id: refreshKey(now: context.date)) {
          do {
            try await library.loadLocal()
            let entries = NotesFeed.entries(
              items: library.items, diamondNotes: library.progressNotes,
              coloringNotes: library.coloringPageProgressNotes)
            count = CraftingStreak.count(
              noteDates: entries.map { $0.note.date }, now: context.date, timeZone: timeZone)
          } catch {
            return
          }
        }
    }
  }

  private func refreshKey(now: Date) -> String {
    "\(library.generation):\(DetailDateOnly.string(from: now, timeZone: timeZone)):\(timeZone.identifier)"
  }

  @ViewBuilder private var pill: some View {
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
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
      }
      .buttonStyle(.plain)
      .glassEffect(.regular.interactive(), in: .capsule)
      .accessibilityLabel("\(count)-day crafting streak")
      .accessibilityHint("Opens Notes")
      .accessibilityIdentifier("home.craftingStreak")
    }
  }
}
