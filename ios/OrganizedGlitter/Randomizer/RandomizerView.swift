import SwiftUI

struct RandomizerView: View {
  @Environment(\.theme) private var theme
  @State private var picker = NumberSectionPicker()
  @FocusState private var isEditing: Bool

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.Spacing.md) {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
          Text("Section numbers")
            .font(.karla(.headline))
          Text("Separate numbers with commas.")
            .foregroundStyle(theme.pageSecondaryForeground)
          TextField("2, 5, 8, 12", text: $picker.numbers, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($isEditing)
            .accessibilityLabel("Section numbers")
            .accessibilityIdentifier("numberSectionInput")
            .accessibilityHint("Whole numbers greater than zero, separated by commas")

          if let error = picker.errorMessage {
            Label(error, systemImage: "exclamationmark.circle")
              .foregroundStyle(theme.destructive)
          }
        }

        if let number = picker.selectedNumber {
          VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Number picked")
              .font(.karla(.headline))
            Text(String(number))
              .font(.karla(.largeTitle).weight(.semibold))
          }
          .accessibilityElement(children: .combine)
        }

        Button {
          isEditing = false
          picker.pick()
          if let error = picker.errorMessage {
            AccessibilityNotification.Announcement(error).post()
          } else if let number = picker.selectedNumber {
            AccessibilityNotification.Announcement("Number picked: \(number)").post()
          }
        } label: {
          Label(picker.selectedNumber == nil ? "Pick a number" : "Pick another", systemImage: "dice")
        }
        .buttonStyle(QuietActionStyle())
      }
      .foregroundStyle(theme.foreground)
      .padding()
      .frame(maxWidth: 600, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .background { theme.themedBackground.ignoresSafeArea() }
    .navigationTitle("Pick a section number")
  }
}
