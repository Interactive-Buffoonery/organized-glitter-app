import SwiftUI

struct LibraryFilterSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @Binding var filters: LibraryFilters
  let section: LibrarySection
  let options: LibraryFilterOptions

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text("Different filters narrow the results together. Multiple selections within one filter match any selection.")
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(theme.pageSecondaryForeground)
        }
        if section == .diamonds {
          singleSelection("Company", options: options.companies,
            selection: $filters.companyID, unavailable: "Unavailable company")
          singleSelection("Artist", options: options.artists,
            selection: $filters.artistID, unavailable: "Unavailable artist")
          singleSelection("Drill shape", options: options.drillShapes,
            selection: $filters.drillShape, unavailable: "Unavailable drill shape")
          if !options.completionYears.isEmpty || filters.completionYear != nil {
            Section("Finished in") {
              Picker("Finished in", selection: $filters.completionYear) {
                Text("Any").tag(Int?.none)
                ForEach(years, id: \.self) { year in
                  Text(String(year)).tag(Optional(year))
                    .accessibilityIdentifier("library.filter.year.\(year)")
                }
              }
              .pickerStyle(.inline)
              .accessibilityIdentifier("library.filter.year")
            }
          }
        } else if section == .books {
          multipleSelection("Publisher", options: options.publishers,
            selection: $filters.publisherIDs, unavailable: "Unavailable publisher")
          multipleSelection("Illustrator", options: options.illustrators,
            selection: $filters.illustratorIDs, unavailable: "Unavailable illustrator")
        }
        if !options.tags.isEmpty || !filters.tagIDs.isEmpty {
          Section {
            selectionRows(options: includingUnavailable(options.tags, selected: filters.tagIDs,
              label: "Unavailable tag"), selection: $filters.tagIDs, facet: "Tags")
          } header: {
            Text("Tags")
          } footer: {
            Text("Shows items with any selected tag.")
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .font(.karla(.body))
      .scrollContentBackground(.hidden)
      .background(theme.themedBackground.ignoresSafeArea())
      .navigationTitle(section == .diamonds ? "Filter diamond art" : "Filter coloring books")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Reset") {
            filters = LibraryFilters()
            AccessibilityNotification.Announcement("Filters reset").post()
          }
            .disabled(filters.isEmpty)
            .accessibilityIdentifier("library.filters.reset")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            AccessibilityNotification.Announcement("Filters applied").post()
            dismiss()
          }
            .accessibilityIdentifier("library.filters.done")
        }
      }
    }
    .tint(theme.primary)
    .presentationSizing(.form)
  }

  private var years: [Int] {
    Set(options.completionYears + [filters.completionYear].compactMap { $0 }).sorted(by: >)
  }

  @ViewBuilder
  private func singleSelection(_ title: String, options: [LibraryFilterOption],
    selection: Binding<String?>, unavailable: String) -> some View
  {
    if !options.isEmpty || selection.wrappedValue != nil {
      Section(title) {
        Picker(title, selection: selection) {
          Text("Any").tag(String?.none)
          ForEach(includingUnavailable(options, selected: Set([selection.wrappedValue].compactMap { $0 }),
            label: unavailable)) { option in
            Text(option.name)
              .fixedSize(horizontal: false, vertical: true)
              .tag(Optional(option.id))
              .accessibilityIdentifier("library.filter.\(title).\(option.id)")
          }
        }
        .pickerStyle(.inline)
        .accessibilityIdentifier("library.filter.\(title)")
      }
    }
  }

  @ViewBuilder
  private func multipleSelection(_ title: String, options: [LibraryFilterOption],
    selection: Binding<Set<String>>, unavailable: String) -> some View
  {
    if !options.isEmpty || !selection.wrappedValue.isEmpty {
      Section(title) {
        selectionRows(options: includingUnavailable(options, selected: selection.wrappedValue,
          label: unavailable), selection: selection, facet: title)
      }
    }
  }

  private func selectionRows(options: [LibraryFilterOption], selection: Binding<Set<String>>,
    facet: String) -> some View
  {
    ForEach(options) { option in
      let selected = selection.wrappedValue.contains(option.id)
      Button {
        if selected { selection.wrappedValue.remove(option.id) }
        else { selection.wrappedValue.insert(option.id) }
      } label: {
        HStack(alignment: .firstTextBaseline) {
          Text(option.name)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(theme.foreground)
          Spacer(minLength: 12)
          if selected { Image(systemName: "checkmark").foregroundStyle(theme.primary) }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .accessibilityLabel(option.name)
      .accessibilityValue(selected ? "Selected" : "Not selected")
      .accessibilityIdentifier("library.filter.\(facet).\(option.id)")
    }
  }

  private func includingUnavailable(_ options: [LibraryFilterOption], selected: Set<String>,
    label: String) -> [LibraryFilterOption]
  {
    let known = Set(options.map(\.id))
    return options + selected.subtracting(known).sorted().map {
      LibraryFilterOption(id: $0, name: label)
    }
  }
}
