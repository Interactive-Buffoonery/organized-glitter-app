import SwiftUI

struct ListMultiSelectRows: View {
  let options: [NamedRelationRecord]
  @Binding var selection: Set<String>
  var isDisabled = false
  var selectionLimit: Int?
  @Environment(\.theme) private var theme

  var body: some View {
    ForEach(options, id: \.id) { option in
      Button {
        if selection.contains(option.id) { selection.remove(option.id) }
        else { selection.insert(option.id) }
      } label: {
        HStack(alignment: .firstTextBaseline) {
          Text(option.name)
            .foregroundStyle(theme.cardForeground)
            .fixedSize(horizontal: false, vertical: true)
          Spacer()
          if selection.contains(option.id) {
            Image(systemName: "checkmark")
              .foregroundStyle(theme.primary)
              .accessibilityHidden(true)
          }
        }
      }
      .frame(minHeight: 44)
      .disabled(isDisabled || (!selection.contains(option.id) && selection.count >= (selectionLimit ?? .max)))
      .accessibilityLabel(option.name)
      .accessibilityAddTraits(selection.contains(option.id) ? .isSelected : [])
    }
  }
}
