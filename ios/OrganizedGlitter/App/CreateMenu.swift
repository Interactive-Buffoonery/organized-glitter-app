import SwiftUI

/// The toolbar `+`. Create is an action, not a destination, so it lives here
/// instead of in a tab. Coloring pages are created from their book.
struct CreateMenu: View {
  @Environment(FormDrawer.self) private var formDrawer
  let library: LibrarySession
  let verticals: VerticalPreferences
  let onRefresh: () async -> Void
  let onSaved: (LibraryItem) -> Void

  var body: some View {
    Menu {
      if verticals.diamondPainting {
        Button("Diamond painting project", systemImage: "diamond") { present(.diamond) }
          .accessibilityIdentifier("create.diamond")
      }
      if verticals.coloringBooks {
        Button("Coloring book", systemImage: "books.vertical") { present(.book) }
          .accessibilityIdentifier("create.book")
      }
    } label: {
      Label("Create", systemImage: "plus")
    }
    .disabled(!verticals.diamondPainting && !verticals.coloringBooks)
    .accessibilityIdentifier("create.menu")
  }

  private func present(_ target: CreateTarget) {
    formDrawer.present(detents: [.large]) {
      CreateEditor(target: target, library: library, onRefresh: onRefresh, onSaved: onSaved)
    }
  }
}

enum CreateTarget: String, Identifiable {
  case diamond
  case book

  var id: Self { self }
}

struct CreateEditor: View {
  let target: CreateTarget
  let library: LibrarySession
  let onRefresh: () async -> Void
  let onSaved: (LibraryItem) -> Void

  var body: some View {
    switch target {
    case .diamond:
      DiamondProjectEditor(library: library, onLibraryRefresh: onRefresh) {
        onSaved(.diamond($0))
      }
    case .book:
      ColoringBookEditor(library: library, onLibraryRefresh: onRefresh) {
        onSaved(.book($0))
      }
    }
  }
}
