import SwiftUI

/// The toolbar `+`. Create is an action, not a destination, so it lives here
/// instead of in a tab. Coloring pages are created from their book.
struct CreateMenu: View {
  let client: PocketBaseClient
  let userID: String
  let verticals: VerticalPreferences
  let onRefresh: () async -> Void
  let onSaved: (LibraryItem) -> Void

  @State private var target: CreateTarget?

  var body: some View {
    Menu {
      if verticals.diamondPainting {
        Button("Diamond painting project", systemImage: "sparkles.rectangle.stack") { target = .diamond }
          .accessibilityIdentifier("create.diamond")
      }
      if verticals.coloringBooks {
        Button("Coloring book", systemImage: "books.vertical") { target = .book }
          .accessibilityIdentifier("create.book")
      }
    } label: {
      Label("Create", systemImage: "plus")
    }
    .disabled(!verticals.diamondPainting && !verticals.coloringBooks)
    .accessibilityIdentifier("create.menu")
    .sheet(item: $target) { target in
      CreateEditor(
        target: target, client: client, userID: userID, onRefresh: onRefresh, onSaved: onSaved)
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
  let client: PocketBaseClient
  let userID: String
  let onRefresh: () async -> Void
  let onSaved: (LibraryItem) -> Void

  var body: some View {
    switch target {
    case .diamond:
      DiamondProjectEditor(client: client, userID: userID, onLibraryRefresh: onRefresh) {
        onSaved(.diamond($0))
      }
    case .book:
      ColoringBookEditor(client: client, userID: userID, onLibraryRefresh: onRefresh) {
        onSaved(.book($0))
      }
    }
  }
}
