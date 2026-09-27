import SwiftUI

/// Form row that picks a user-scoped taxonomy record (publisher/illustrator).
/// `selection` is the record id; "" means none (PocketBase relation-clear sentinel).
/// Must be hosted inside a NavigationStack (both coloring editors provide one).
struct TaxonomyPicker: View {
  let library: LibrarySession
  let userID: String
  let collection: String
  let label: String
  let initialName: String?
  @Binding var selection: String

  // Options live here (not in the pushed list) so the row can show the picked
  // name after the list pops, including a record created moments ago.
  @State private var options: [NamedRelationRecord]?

  var body: some View {
    NavigationLink {
      TaxonomyOptionList(
        library: library,
        userID: userID,
        collection: collection,
        label: label,
        selection: $selection,
        options: $options
      )
    } label: {
      LabeledContent(label, value: displayName)
    }
    .accessibilityIdentifier("\(label.lowercased())Picker")
  }

  private var displayName: String {
    if let name = options?.first(where: { $0.id == selection })?.name {
      name
    } else if !selection.isEmpty, let initialName {
      initialName
    } else {
      "None"
    }
  }
}

private struct TaxonomyOptionList: View {
  let library: LibrarySession
  let userID: String
  let collection: String
  let label: String
  @Binding var selection: String
  @Binding var options: [NamedRelationRecord]?

  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @State private var errorMessage: String?
  @State private var isCreating = false
  @State private var newName = ""

  var body: some View {
    List {
      Group {
        if let options {
          Section {
            selectionRow(id: "", name: "None")
            ForEach(options, id: \.id) { option in
              selectionRow(id: option.id, name: option.name)
            }
          }

          Section {
            if let errorMessage {
              AccessibleErrorLabel(message: errorMessage)
            }
            HStack {
              TextField("New \(label.lowercased())", text: $newName)
                .submitLabel(.done)
                .onSubmit { Task { await create() } }
                .disabled(isCreating)
                .accessibilityIdentifier("taxonomy.newName")
              if isCreating {
                ProgressView()
              } else {
                Button("Add") {
                  Task { await create() }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.primary)
                .disabled(trimmedNewName.isEmpty)
                .accessibilityLabel("Add \(label.lowercased())")
                .accessibilityIdentifier("taxonomy.add")
              }
            }
          } footer: {
            Text("Adding a \(label.lowercased()) needs a connection.")
          }
        } else if let errorMessage {
          Section {
            AccessibleErrorLabel(message: errorMessage)
            Button("Try Again") {
              Task { await load() }
            }
          }
        } else {
          Section {
            ProgressView()
              .frame(maxWidth: .infinity)
          }
        }
      }
      .listRowBackground(theme.card)
    }
    .themedScrollBackground()
    .navigationTitle(label)
    .navigationBarTitleDisplayMode(.inline)
    .task {
      guard options == nil else {
        return
      }
      await load()
    }
  }

  private var trimmedNewName: String {
    newName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func selectionRow(id: String, name: String) -> some View {
    Button {
      selection = id
      dismiss()
    } label: {
      HStack {
        Text(name)
          .foregroundStyle(theme.cardForeground)
        Spacer()
        if selection == id {
          Image(systemName: "checkmark")
            .foregroundStyle(theme.primary)
            .accessibilityHidden(true)
        }
      }
    }
    .accessibilityAddTraits(selection == id ? .isSelected : [])
  }

  private func load() async {
    errorMessage = nil
    do {
      let records: [NamedRelationRecord] = try await library.client.allRecords(
        collection: collection,
        filter: PocketBaseFilter.equals(.user, userID),
        sort: "+name"
      )
      options = records
    } catch APIError.cancelled {
      return
    } catch {
      errorMessage = message(
        error,
        permission: "Your account does not have permission to view \(label.lowercased()) options.",
        fallback: "\(label) options are unavailable right now. Try again."
      )
    }
  }

  private func create() async {
    let name = trimmedNewName
    guard !name.isEmpty, !isCreating else {
      return
    }

    isCreating = true
    errorMessage = nil
    defer { isCreating = false }

    do {
      let created: NamedRelationRecord = try await library.create(
        collection: collection,
        body: TaxonomyWrite(user: userID, name: name)
      )
      var updated = options ?? []
      let index =
        updated.firstIndex {
          created.name.localizedCaseInsensitiveCompare($0.name) == .orderedAscending
        } ?? updated.endIndex
      updated.insert(created, at: index)
      options = updated
      newName = ""
      selection = created.id
      dismiss()
    } catch APIError.cancelled {
      return
    } catch {
      errorMessage = message(
        error,
        permission: "Your account does not have permission to add a \(label.lowercased()).",
        fallback: "The \(label.lowercased()) could not be created. Try again."
      )
    }
  }

  private func message(_ error: Error, permission: String, fallback: String) -> String {
    error as? APIError == .offline
      ? APIError.offlineMessage
      : error.userMessage(permission: permission, fallback: fallback)
  }
}

private struct TaxonomyWrite: Encodable {
  let user: String
  let name: String
}
