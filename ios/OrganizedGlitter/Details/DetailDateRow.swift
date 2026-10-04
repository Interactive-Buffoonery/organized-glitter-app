import SwiftUI

/// A date-only field edited in place, committed only after the picker closes.
struct DetailDateRow: View {
  @Environment(FormDrawer.self) private var formDrawer
  @Environment(\.theme) private var theme
  @State private var isEditingDate = false
  @State private var draftDate = Date.now

  let label: String
  let value: String?
  let isDisabled: Bool
  var minimumDate: Date? = nil
  var maximumDate: Date? = nil
  let onChange: (Date?) -> Void

  var body: some View {
    let storedDate = value.flatMap { DetailDateOnly.date($0) }
    let formattedDate = storedDate.map { DetailDateOnly.formatted($0) }
    let storedDateString = storedDate.map { DetailDateOnly.string(from: $0) }
    let upperBound = maximumDate ?? .distantFuture
    let lowerBound = minimumDate ?? .distantPast
    let pickerRange = min(lowerBound, upperBound)...upperBound
    DetailMetadataRow(label: label, combinesChildren: false) {
      HStack(spacing: 0) {
        Button {
          draftDate = min(max(storedDate ?? .now, pickerRange.lowerBound), pickerRange.upperBound)
          isEditingDate = true
        } label: {
          if let formatted = formattedDate {
            Text(formatted)
              .frame(minHeight: 44)
              .contentShape(.rect)
          } else {
            Label("Add date", systemImage: "plus")
              .frame(minHeight: 44)
              .contentShape(.rect)
          }
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.pageAction)
        .accessibilityLabel(storedDate == nil
          ? "Add \(label.lowercased()) date" : "Change \(label.lowercased()) date")
        .accessibilityValue(formattedDate ?? "No date")
        if storedDate != nil {
          Button {
            onChange(nil)
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(theme.pageSecondaryForeground)
              .frame(width: 44, height: 44)
              .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Clear \(label.lowercased()) date")
        }
      }
    }
    .disabledWhileFormPresented(formDrawer, or: isDisabled)
    .accessibilityIdentifier("detail.date.\(label.lowercased())")
    .onChange(of: formDrawer.isPresenting) { _, isPresenting in
      if isPresenting { isEditingDate = false }
    }
    .popover(isPresented: $isEditingDate) {
      VStack(alignment: .leading, spacing: 16) {
        Text("\(storedDate == nil ? "Add" : "Change") \(label.lowercased()) date")
          .font(.karla(.headline))
          .foregroundStyle(theme.foreground)
        DatePicker(label, selection: $draftDate, in: pickerRange, displayedComponents: .date)
          .datePickerStyle(.graphical)
        HStack {
          Button("Cancel") { isEditingDate = false }
          Spacer()
          Button("Save") {
            guard !formDrawer.isPresenting, !isDisabled else { return }
            isEditingDate = false
            if storedDateString
              != DetailDateOnly.string(from: draftDate)
            {
              onChange(draftDate)
            }
          }
          .buttonStyle(.borderedProminent)
          .disabledWhileFormPresented(formDrawer, or: isDisabled)
        }
      }
      .padding()
      .frame(maxWidth: 380)
      .background(theme.card)
      .presentationCompactAdaptation(.sheet)
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
  }
}
