import SwiftUI

/// Form row that picks a user-scoped taxonomy record (publisher/illustrator).
/// `selection` is the record id; "" means none (PocketBase relation-clear sentinel).
/// Must be hosted inside a NavigationStack (both coloring editors provide one).
struct TaxonomyPicker: View {
  let client: PocketBaseClient
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
        client: client,
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
  let client: PocketBaseClient
  let userID: String
  let collection: String
  let label: String
  @Binding var selection: String
  @Binding var options: [NamedRelationRecord]?

  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @State private var errorMessage: String?
  @State private var isCreating = false
  @State private var isPresentingCreate = false
  @State private var newName = ""

  var body: some View {
    List {
      if let options {
        Section {
          selectionRow(id: "", name: "None")
          ForEach(options, id: \.id) { option in
            selectionRow(id: option.id, name: option.name)
          }
        }
        .listRowBackground(theme.card)

        Section {
          if let errorMessage {
            AccessibleErrorLabel(message: errorMessage)
          }
          Button {
            isPresentingCreate = true
          } label: {
            Label("New \(label.lowercased())…", systemImage: "plus.circle")
              .foregroundStyle(theme.primary)
          }
          .disabled(isCreating)
        }
        .listRowBackground(theme.card)
      } else if let errorMessage {
        Section {
          AccessibleErrorLabel(message: errorMessage)
          Button("Try Again") {
            Task { await load() }
          }
        }
        .listRowBackground(theme.card)
      } else {
        Section {
          ProgressView()
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(theme.card)
      }
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
    .alert("New \(label)", isPresented: $isPresentingCreate) {
      TextField("Name", text: $newName)
      Button("Create") {
        Task { await create() }
      }
      .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      Button("Cancel", role: .cancel) {
        newName = ""
      }
    }
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
      let records: [NamedRelationRecord] = try await client.allRecords(
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
    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !isCreating else {
      return
    }

    isCreating = true
    errorMessage = nil
    defer { isCreating = false }

    do {
      let created: NamedRelationRecord = try await client.create(
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
