import SwiftUI

struct MysteryPagePlaceholder: View {
  let pageNumber: Int
  @Environment(\.theme) private var theme

  var body: some View {
    theme.card
      .aspectRatio(4 / 5, contentMode: .fit)
      .overlay {
        ViewThatFits {
          VStack(spacing: 8) {
            Text("Page \(pageNumber)")
              .font(.karla(.headline))
              .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "questionmark")
              .font(.karla(.title2))
          }
          .padding(12)
          Image(systemName: "questionmark")
            .font(.karla(.title2))
        }
        .foregroundStyle(theme.pageSecondaryForeground)
      }
      .clipShape(.rect(cornerRadius: Theme.Radius.medium))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Page \(pageNumber), mystery")
  }
}
