import SwiftUI

struct QuickCreateView: View {
  @Environment(\.theme) private var theme

  let client: PocketBaseClient
  let userID: String
  let libraryRefresh: LibraryRefresh
  let verticals: VerticalPreferences

  @State private var isCreatingDiamond = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.Spacing.md) {
        PageHeader("Create", subtitle: "Start something sparkly.")

        if verticals.diamondPainting {
          Button {
            isCreatingDiamond = true
          } label: {
            CreateActionCard(
              title: "New diamond project",
              systemImage: "diamond",
              surfaceIndex: 0,
              isEnabled: true
            )
          }
          .buttonStyle(.plain)
        }

        if verticals.coloringBooks {
          CreateActionCard(
            title: "New coloring book", systemImage: "book.closed", surfaceIndex: 1)
          CreateActionCard(
            title: "New coloring page", systemImage: "doc.richtext", surfaceIndex: 2)
        }

        SectionHeader("Log")
          .padding(.top, Theme.Spacing.sm)

        CreateActionCard(
          title: "Add progress note", systemImage: "square.and.pencil", surfaceIndex: 4)
      }
      .padding()
    }
    .background(theme.backgroundGradient)
    .navigationTitle("Create")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isCreatingDiamond) {
      DiamondProjectEditor(
        client: client,
        userID: userID,
        onLibraryRefresh: { libraryRefresh.bump() }
      ) { _ in
        libraryRefresh.bump()
      }
    }
  }
}

/// Stub entries render with a "Soon" tag instead of a chevron until their
/// editors are wired up.
private struct CreateActionCard: View {
  @Environment(\.theme) private var theme

  let title: String
  let systemImage: String
  let surfaceIndex: Int
  var isEnabled = false

  var body: some View {
    HStack(spacing: 12) {
      IconBadge(systemImage: systemImage, surfaceIndex: (surfaceIndex + 2) % 5)
      Text(title)
        .font(.headline)
      Spacer(minLength: 8)
      if isEnabled {
        Image(systemName: "chevron.right")
          .font(.subheadline.weight(.semibold))
          .accessibilityHidden(true)
      } else {
        Text("Soon")
          .font(.caption.weight(.semibold))
          .foregroundStyle(theme.surfaceMutedForeground)
      }
    }
    .padding(14)
    .stickerCard(surfaceIndex)
    .accessibilityElement(children: .combine)
  }
}
