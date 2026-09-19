import SwiftUI

struct LibraryItemDetail: View {
  @Environment(\.theme) private var theme

  let item: LibraryItem
  var imageURL: URL? = nil
  var onEdit: (() -> Void)?
  var onDelete: (() -> Void)?
  var deleteLabel: String = "Delete Project"

  var body: some View {
    List {
      Section {
        if let imageURL {
          AsyncImage(url: imageURL) { image in
            image
              .resizable()
              .scaledToFill()
          } placeholder: {
            RoundedRectangle(cornerRadius: Theme.Radius.medium)
              .fill(theme.muted)
              .overlay {
                Image(systemName: kindSystemImage)
                  .font(.title)
                  .foregroundStyle(theme.mutedForeground)
              }
          }
          .frame(width: detailImageSize.width, height: detailImageSize.height)
          .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
          .accessibilityLabel(item.artworkAccessibilityLabel)
        }

        VStack(alignment: .leading, spacing: 12) {
          Text(item.title)
            .font(.largeTitle.bold())
          if !item.subtitle.isEmpty {
            Text(item.subtitle)
              .foregroundStyle(.secondary)
          }
          StatusBadge(status: item.status)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
      }
      .listRowBackground(theme.card)

      Group {
        switch item {
        case .diamond(let project):
          Section("Project") {
            LabeledContent("Kit", value: project.kitCategory.organizedGlitterLabel)
            LabeledContent(
              "Drill shape",
              value: project.drillShape?.nonEmpty?.organizedGlitterLabel ?? "Not set"
            )
            if let width = project.width, let height = project.height {
              LabeledContent("Size", value: "\(width.formatted()) × \(height.formatted()) cm")
            }
          }
        case .book(let book):
          Section("Progress") {
            LabeledContent("Completed", value: "\(book.completedPages ?? 0) of \(book.totalPages)")
            ProgressView(value: book.completionPercentage ?? 0, total: 100)
              .accessibilityLabel("Book completion")
          }
        case .page(let page):
          Section("Page") {
            LabeledContent("Page number", value: page.pageNumber.formatted())
            LabeledContent("Book", value: page.expand?.book?.title ?? "Unknown book")
          }
        }
      }
      .listRowBackground(theme.card)
    }
    .themedScrollBackground()
    .navigationTitle(item.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if let onEdit {
        ToolbarItem {
          Button("Edit", action: onEdit)
        }
      }
      if let onDelete {
        ToolbarItem {
          Menu {
            Button(deleteLabel, role: .destructive, action: onDelete)
          } label: {
            Label("More", systemImage: "ellipsis.circle")
          }
        }
      }
    }
  }

  private var kindSystemImage: String {
    switch item {
    case .diamond: "diamond"
    case .book: "book.closed"
    case .page: "doc.richtext"
    }
  }

  private var detailImageSize: CGSize {
    switch item {
    case .book: CGSize(width: 160, height: 220)
    default: CGSize(width: 160, height: 160)
    }
  }
}
