import SwiftUI

/// The toolbar `+`. Create is an action, not a destination, so it lives here
/// instead of in a tab. Coloring pages are generated through their book.
struct CreateMenu: View {
  @Environment(FormDrawer.self) private var formDrawer
  let library: LibrarySession
  let verticals: VerticalPreferences
  let onRefresh: () async -> Void
  let onSaved: (LibraryItem) -> Void
  let onAddNote: () -> Void

  var body: some View {
    Menu {
      NeedsConnectionHint()
      if verticals.diamondPainting {
        Button("Diamond painting project", systemImage: LibrarySection.diamonds.systemImage) { present(.diamond) }
          .accessibilityIdentifier("create.diamond")
      }
      if verticals.coloringBooks {
        Button("Coloring book", systemImage: LibrarySection.books.systemImage) { present(.book) }
          .accessibilityIdentifier("create.book")
      }
      if verticals.coloringBooks {
        Button("Coloring pages", systemImage: LibrarySection.pages.systemImage) { present(.page) }
          .accessibilityIdentifier("create.page")
      }
      if verticals.hasEnabledVertical {
        Button("Progress note", systemImage: "square.and.pencil", action: onAddNote)
          .accessibilityIdentifier("create.note")
      }
    } label: {
      Label("Create", systemImage: "plus")
    }
    .disabledWhileFormPresented(
      formDrawer, or: !verticals.diamondPainting && !verticals.coloringBooks)
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
  case page

  var id: Self { self }

  var title: String {
    switch self {
    case .diamond: "diamond painting"
    case .book: "coloring book"
    case .page: "coloring pages"
    }
  }
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
    case .page:
      PageCreationBookPicker(library: library) { onSaved(.book($0)) }
    }
  }
}

private struct PageCreationBookPicker: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @State private var selectedBook: ColoringBookRecord?
  let library: LibrarySession
  let onSaved: (ColoringBookRecord) -> Void

  private var books: [ColoringBookRecord] {
    library.items.compactMap { item in
      guard case .book(let book) = item, book.user == library.userID else { return nil }
      return book
    }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
  }

  var body: some View {
    if let selectedBook {
      ColoringBookPageCountEditor(library: library, book: selectedBook, onSaved: onSaved)
    } else {
      NavigationStack {
        List {
          Section {
            ForEach(books) { book in
              Button(book.title) { selectedBook = book }
                .foregroundStyle(theme.foreground)
                .accessibilityLabel("Add pages to \(book.title)")
            }
          } header: {
            Text("Choose a coloring book")
          } footer: {
            Text("Increase the book’s page count to generate more pages.")
          }
          .listRowBackground(theme.card)
        }
        .overlay {
          if books.isEmpty {
            ContentUnavailableView(
              "Add a book first", systemImage: "books.vertical",
              description: Text("Pages belong to a coloring book. Add a book from the + menu."))
          }
        }
        .themedScrollBackground()
        .navigationTitle("Add coloring pages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
          }
        }
      }
    }
  }
}
