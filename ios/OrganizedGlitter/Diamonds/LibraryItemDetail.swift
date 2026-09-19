import SwiftUI

struct LibraryItemDetailDestination: View {
  @Environment(\.dismiss) private var dismiss
  @State private var model: LibraryItemDetailModel
  @State private var editor: DetailEditor?
  @State private var isConfirmingDelete = false

  let onCollectionChanged: @MainActor @Sendable () async -> Void

  init(
    item: LibraryItem,
    client: PocketBaseClient,
    userID: String,
    onCollectionChanged: @escaping @MainActor @Sendable () async -> Void
  ) {
    _model = State(
      initialValue: LibraryItemDetailModel(item: item, client: client, userID: userID))
    self.onCollectionChanged = onCollectionChanged
  }

  var body: some View {
    Group {
      switch model.item {
      case .diamond(let project):
        DiamondProjectDetailView(
          project: project,
          model: model,
          onCollectionChanged: onCollectionChanged
        )
        .accessibilityIdentifier("detail.diamond")
      case .book(let book):
        ColoringBookDetailView(book: book, model: model) {
          editor = .book(book)
        }
        .accessibilityIdentifier("detail.book")
      case .page(let page):
        ColoringPageDetailView(
          page: page,
          model: model,
          onCollectionChanged: onCollectionChanged
        )
        .accessibilityIdentifier("detail.page")
      }
    }
    .navigationTitle(model.item.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button("Edit") {
          editor = DetailEditor(item: model.item)
        }
        .disabled(model.isMutating)
        .accessibilityIdentifier("detail.edit")

        if model.item.canDeleteFromDetail {
          Menu {
            Button(model.item.deleteLabel, role: .destructive) {
              isConfirmingDelete = true
            }
            .accessibilityIdentifier("detail.delete")
          } label: {
            Label("More", systemImage: "ellipsis.circle")
          }
          .disabled(model.isMutating)
          .accessibilityIdentifier("detail.more")
        }
      }
    }
    .task {
      await model.load()
    }
    .onAppear {
      guard model.hasLoaded, case .book = model.item else { return }
      Task { await model.load() }
    }
    .sheet(item: $editor) { editor in
      editorView(for: editor)
    }
    .confirmationDialog(
      "Delete \(model.item.title)?",
      isPresented: $isConfirmingDelete,
      titleVisibility: .visible
    ) {
      Button(model.item.deleteLabel, role: .destructive) {
        Task {
          if await model.deleteItem() {
            await onCollectionChanged()
            dismiss()
          }
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(model.item.deleteMessage)
    }
  }

  @ViewBuilder
  private func editorView(for editor: DetailEditor) -> some View {
    switch editor {
    case .diamond(let project):
      DiamondProjectEditor(
        client: model.client,
        userID: model.userID,
        project: project,
        onLibraryRefresh: refreshCollection,
        onSaved: { saved in
          Task { await acceptSaved(.diamond(saved)) }
        }
      )
    case .book(let book):
      ColoringBookEditor(
        client: model.client,
        userID: model.userID,
        book: book,
        onLibraryRefresh: refreshCollection,
        onSaved: { saved in
          Task { await acceptSaved(.book(saved)) }
        }
      )
    case .page(let page):
      ColoringPageEditor(
        client: model.client,
        page: page,
        onLibraryRefresh: refreshCollection,
        onSaved: { saved in
          Task { await acceptSaved(.page(saved)) }
        }
      )
    }
  }

  private func acceptSaved(_ item: LibraryItem) async {
    await model.acceptSaved(item)
    await onCollectionChanged()
  }

  private func refreshCollection() async {
    await model.load()
    await onCollectionChanged()
  }
}

private enum DetailEditor: Identifiable {
  case diamond(DiamondProjectRecord)
  case book(ColoringBookRecord)
  case page(ColoringPageRecord)

  init(item: LibraryItem) {
    switch item {
    case .diamond(let project): self = .diamond(project)
    case .book(let book): self = .book(book)
    case .page(let page): self = .page(page)
    }
  }

  var id: String {
    switch self {
    case .diamond(let project): "diamond:\(project.id)"
    case .book(let book): "book:\(book.id)"
    case .page(let page): "page:\(page.id)"
    }
  }
}

extension LibraryItem {
  fileprivate var canDeleteFromDetail: Bool {
    if case .page = self { return false }
    return true
  }

  fileprivate var deleteLabel: String {
    switch self {
    case .diamond: "Delete Project"
    case .book: "Delete Book"
    case .page: ""
    }
  }

  fileprivate var deleteMessage: String {
    switch self {
    case .diamond:
      "This deletes the project and its progress notes."
    case .book:
      "This deletes the book and its generated pages."
    case .page:
      ""
    }
  }
}
