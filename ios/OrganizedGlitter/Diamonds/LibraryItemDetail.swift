import SwiftUI

struct LibraryItemDetailDestination: View {
  @Environment(FormDrawer.self) private var formDrawer
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @Environment(\.connectionAvailable) private var connectionAvailable
  @State private var model: LibraryItemDetailModel
  @State private var isConfirmingDelete = false
  @State private var deleteErrorMessage: String?
  @Binding private var logEditor: LibraryItemDetailModel?

  let onCollectionChanged: @MainActor @Sendable () async -> Void
  let onEditPageCount: ((ColoringBookRecord) -> Void)?

  init(
    item: LibraryItem,
    library: LibrarySession,
    logEditor: Binding<LibraryItemDetailModel?>,
    onCollectionChanged: @escaping @MainActor @Sendable () async -> Void,
    onEditPageCount: ((ColoringBookRecord) -> Void)? = nil
  ) {
    _model = State(
      initialValue: LibraryItemDetailModel(item: item, library: library))
    _logEditor = logEditor
    self.onCollectionChanged = onCollectionChanged
    self.onEditPageCount = onEditPageCount
  }

  var body: some View {
    Group {
      switch model.item {
      case .diamond(let project):
        DiamondProjectDetailView(
          project: project,
          model: model,
          logEditor: $logEditor,
          onCollectionChanged: onCollectionChanged
        )
        .accessibilityIdentifier("detail.diamond")
      case .book(let book):
        ColoringBookDetailView(
          book: book,
          model: model,
          logEditor: $logEditor,
          onEditPageCount: { onEditPageCount?(book) },
          onCollectionChanged: onCollectionChanged
        )
        .accessibilityIdentifier("detail.book")
      case .page(let page):
        ColoringPageDetailView(
          page: page,
          model: model,
          logEditor: $logEditor,
          onCollectionChanged: onCollectionChanged
        )
        .accessibilityIdentifier("detail.page")
      }
    }
    .navigationTitle(model.item.title)
    .navigationBarTitleDisplayMode(.inline)
    .background {
      theme.themedBackground.ignoresSafeArea()
    }
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button("Edit") {
          let editor = DetailEditor(item: model.item)
          formDrawer.present(detents: editor.detents) {
            editorView(for: editor)
          }
        }
        .disabledWhileFormPresented(formDrawer, or: model.isMutating)
        .accessibilityIdentifier("detail.edit")

        if model.item.canDeleteFromDetail {
          Menu {
            NeedsConnectionHint()
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
      if !model.hasLoaded {
        await model.load()
      }
    }
    .onChange(of: model.library.generation) { _, _ in
      Task { await model.load(preservingLoadedBookPages: true) }
    }
    .onAppear {
      guard model.hasLoaded, model.needsBookPageRefresh, case .book = model.item else {
        return
      }
      model.needsBookPageRefresh = false
      Task {
        if !(await model.load(preservingLoadedBookPages: true)) {
          model.needsBookPageRefresh = true
        }
      }
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
          } else if let message = model.mutationErrorMessage {
            deleteErrorMessage = message
            model.mutationErrorMessage = nil
          }
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(model.item.deleteMessage
        + (connectionAvailable ? "" : " " + APIError.deleteNeedsConnectionMessage))
    }
    .alert(
      "Couldn’t delete item",
      isPresented: Binding(
        get: { deleteErrorMessage != nil },
        set: { if !$0 { deleteErrorMessage = nil } }
      )
    ) {
      Button("OK") { deleteErrorMessage = nil }
    } message: {
      Text(deleteErrorMessage ?? "")
    }
  }

  @ViewBuilder
  private func editorView(for editor: DetailEditor) -> some View {
    switch editor {
    case .diamond(let project):
      DiamondProjectEditor(
        library: model.library,
        project: project,
        onLibraryRefresh: refreshCollection,
        onSaved: { saved in
          Task { await acceptSaved(.diamond(saved)) }
        }
      )
    case .book(let book):
      ColoringBookEditor(
        library: model.library,
        book: book,
        onLibraryRefresh: refreshCollection,
        onSaved: { saved in
          Task { await acceptSaved(.book(saved)) }
        }
      )
    case .page(let page):
      ColoringPageEditor(
        library: model.library,
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

  var detents: Set<PresentationDetent> {
    switch self {
    case .diamond, .page: [.medium, .large]
    case .book: [.large]
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
