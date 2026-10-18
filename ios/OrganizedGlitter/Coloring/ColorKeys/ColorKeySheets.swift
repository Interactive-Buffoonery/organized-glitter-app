import SwiftUI

/// Search, recently used symbols, then the catalog by group.
struct SymbolPickerView: View {
  @Environment(\.theme) private var theme
  @ScaledMetric(relativeTo: .title) private var cellSize: CGFloat = 52
  @State private var query = ""

  let recentSymbols: [String]
  let onPick: (String) -> Void
  var catalog: SymbolCatalog = .bundled

  var body: some View {
    let results = catalog.search(query)
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 20) {
        if query.isEmpty, !recentSymbols.isEmpty {
          section("Recently used") {
            ScrollView(.horizontal) {
              LazyHStack(spacing: 8) { ForEach(recentSymbols, id: \.self, content: cell) }
            }
            .scrollIndicators(.hidden)
          }
        }
        ForEach(catalog.grouped(results)) { group in
          section(group.group.label) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cellSize + 8), spacing: 8)], spacing: 8) {
              ForEach(group.symbols.map(\.id), id: \.self, content: cell)
            }
          }
        }
        if results.isEmpty {
          ContentUnavailableView.search(text: query)
        }
        Text("Can’t find your symbol? Send us a photo and we’ll add it.")
          .font(.karla(.footnote))
          .foregroundStyle(theme.mutedForeground)
          .frame(maxWidth: .infinity, alignment: .center)
          .multilineTextAlignment(.center)
          .accessibilityIdentifier("symbolPicker.footer")
      }
      .padding(20)
    }
    .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search symbols")
    .navigationTitle("Choose a symbol")
    .navigationBarTitleDisplayMode(.inline)
    .background(theme.themedBackground.ignoresSafeArea())
  }

  private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.karla(.headline))
        .foregroundStyle(theme.foreground)
        .accessibilityAddTraits(.isHeader)
      content()
    }
  }

  private func cell(_ id: String) -> some View {
    Button { onPick(id) } label: {
      ColorKeySymbolView(id: id, size: cellSize * 0.75, catalog: catalog)
        .frame(width: cellSize, height: cellSize)
        .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("symbolPicker.\(id)")
  }
}

/// First run on a page with no keys: 1-9, 0 and a-z start on; extras come from the picker.
struct ColorKeySetupSheet: View {
  @Environment(\.connectionAvailable) private var connectionAvailable
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @ScaledMetric(relativeTo: .title) private var cellSize: CGFloat = 48

  let recentSymbols: [String]
  let onSave: (_ symbols: [String]) async -> String?

  @State private var enabled = Set(SymbolCatalog.setupDefaults)
  @State private var extras: [String] = []
  @State private var isPickingExtra = false
  @State private var isSaving = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text("Turn off any symbols that aren’t on this page.")
            .font(.karla(.body))
            .foregroundStyle(theme.foreground)
          LazyVGrid(columns: [GridItem(.adaptive(minimum: cellSize + 8), spacing: 8)], spacing: 8) {
            ForEach(SymbolCatalog.setupDefaults, id: \.self) { id in
              Toggle(isOn: binding(for: id)) {
                ColorKeySymbolView(id: id, size: cellSize * 0.6)
                  .frame(maxWidth: .infinity, minHeight: cellSize)
              }
              .toggleStyle(.button)
              .accessibilityIdentifier("colorKeys.setup.\(id)")
            }
          }
          Text("More symbols")
            .font(.karla(.headline))
            .foregroundStyle(theme.foreground)
            .accessibilityAddTraits(.isHeader)
          if !extras.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cellSize + 8), spacing: 8)], spacing: 8) {
              ForEach(extras, id: \.self) { id in
                Button { extras.removeAll { $0 == id } } label: {
                  ColorKeySymbolView(id: id, size: cellSize * 0.6)
                    .frame(maxWidth: .infinity, minHeight: cellSize)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Remove \(SymbolCatalog.bundled.accessibilityName(for: id))")
              }
            }
          }
          Button("Add symbol", systemImage: "plus") { isPickingExtra = true }
            .frame(minHeight: 44)
            .accessibilityIdentifier("colorKeys.setup.addExtra")
          if isSaving { ProgressView("Saving symbols…") }
          if let errorMessage { AccessibleErrorLabel(message: errorMessage) }
          NeedsConnectionHint()
        }
        .font(.karla(.body))
        .padding(20)
      }
      .background(theme.themedBackground.ignoresSafeArea())
      .navigationTitle("Set up symbols")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Skip") { dismiss() }
            .disabled(isSaving)
            .accessibilityIdentifier("colorKeys.setup.skip")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { Task { await save() } }
            .disabled(isSaving || !connectionAvailable || symbols.isEmpty)
            .accessibilityIdentifier("colorKeys.setup.save")
        }
      }
      .sheet(isPresented: $isPickingExtra) {
        NavigationStack {
          SymbolPickerView(recentSymbols: recentSymbols) { id in
            if !symbols.contains(id) { extras.append(id) }
            isPickingExtra = false
          }
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Cancel", role: .cancel) { isPickingExtra = false }
            }
          }
        }
      }
    }
    .interactiveDismissDisabled(isSaving)
  }

  private var symbols: [String] {
    SymbolCatalog.setupDefaults.filter(enabled.contains) + extras
  }

  private func binding(for id: String) -> Binding<Bool> {
    Binding(get: { enabled.contains(id) }, set: { isOn in
      if isOn { enabled.insert(id) } else { enabled.remove(id) }
    })
  }

  private func save() async {
    isSaving = true
    errorMessage = await onSave(symbols)
    isSaving = false
    if errorMessage == nil { dismiss() }
  }
}

/// Records the color used for one symbol.
struct ColorKeyEntrySheet: View {
  @Environment(\.connectionAvailable) private var connectionAvailable
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 72
  @FocusState private var focusedCode: Bool

  let model: ColorKeysModel
  let id: String?
  let onSaved: (_ saved: ColorKeyRecord, _ advance: Bool) -> Void

  @State private var draft: ColorKeyWrite
  @State private var tried: [TriedColor]
  @State private var errorMessage: String?
  @State private var isConfirmingDelete = false

  init(model: ColorKeysModel, initial: ColorKeyWrite, id: String?,
    onSaved: @escaping (_ saved: ColorKeyRecord, _ advance: Bool) -> Void) {
    self.model = model
    self.id = id
    self.onSaved = onSaved
    _draft = State(initialValue: initial)
    _tried = State(initialValue: initial.tried.map { TriedColor(text: $0) })
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          VStack(spacing: 8) {
            ColorKeySymbolView(id: draft.symbol, size: symbolSize)
            Text(SymbolCatalog.bundled.accessibilityName(for: draft.symbol))
              .font(.karla(.headline))
              .foregroundStyle(theme.foreground)
              .accessibilityHidden(true)
          }
          .frame(maxWidth: .infinity)
        }

        Section("Color") {
          TextField("Code", text: $draft.code)
            .focused($focusedCode)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .accessibilityIdentifier("colorKeys.entry.code")
          if focusedCode {
            ForEach(model.suggestions(for: draft.code), id: \.self) { suggestion in
              Button { apply(suggestion) } label: {
                HStack {
                  Text(suggestion.code).foregroundStyle(theme.foreground)
                  Text(suggestion.colorName).foregroundStyle(theme.mutedForeground)
                  Spacer()
                  SwatchDot(hex: suggestion.swatch)
                }
              }
              .accessibilityLabel("Use \(suggestion.code) \(suggestion.colorName)")
            }
          }
          TextField("Color name", text: $draft.colorName)
            .accessibilityIdentifier("colorKeys.entry.colorName")
          ColorPicker("Swatch", selection: swatch, supportsOpacity: false)
          if !draft.swatch.isEmpty {
            Button("Remove swatch", role: .destructive) { draft.swatch = "" }
          }
        }

        Section("Tried first") {
          ForEach($tried) { $color in
            TextField("Color tried", text: $color.text)
          }
          .onDelete { tried.remove(atOffsets: $0) }
          Button("Add color tried", systemImage: "plus") { tried.append(TriedColor(text: "")) }
            .disabled(tried.count >= ColorKeys.maxTried)
        }

        Section("Note") {
          TextField("Note", text: $draft.note, axis: .vertical)
            .lineLimit(3...8)
        }

        Section {
          if let errorMessage { AccessibleErrorLabel(message: errorMessage) }
          NeedsConnectionHint()
          Button("Save and next") { Task { await save(advance: true) } }
            .disabled(!canSave)
            .accessibilityIdentifier("colorKeys.entry.saveNext")
          if id != nil {
            Button("Delete color", role: .destructive) { isConfirmingDelete = true }
              .disabled(!canSave)
          }
        }
      }
      .font(.karla(.body))
      .scrollContentBackground(.hidden)
      .background(theme.themedBackground.ignoresSafeArea())
      .navigationTitle(id == nil ? "Add color" : "Edit color")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { Task { await save(advance: false) } }
            .disabled(!canSave)
            .accessibilityIdentifier("colorKeys.entry.save")
        }
      }
      .confirmationDialog("Delete this color?", isPresented: $isConfirmingDelete,
        titleVisibility: .visible) {
        Button("Delete", role: .destructive) { Task { await delete() } }
      }
    }
    .interactiveDismissDisabled(model.isSaving)
  }

  private var canSave: Bool { connectionAvailable && !model.isSaving }

  private var swatch: Binding<Color> {
    Binding(get: { Color(swatchHex: draft.swatch) ?? .clear },
      set: { draft.swatch = $0.swatchHex })
  }

  private func apply(_ suggestion: ColorKeySuggestion) {
    draft.code = suggestion.code
    if !suggestion.colorName.isEmpty { draft.colorName = suggestion.colorName }
    if !suggestion.swatch.isEmpty { draft.swatch = suggestion.swatch }
    focusedCode = false
  }

  private func save(advance: Bool) async {
    var write = draft
    write.tried = tried.map(\.text)
    switch await model.save(write, id: id) {
    case .success(let saved): onSaved(saved, advance)
    case .failure(let failure): errorMessage = failure.message
    }
  }

  private func delete() async {
    guard let id, let key = model.keys.first(where: { $0.id == id }) else { return }
    errorMessage = await model.delete(key)
    if errorMessage == nil { dismiss() }
  }
}

private struct TriedColor: Identifiable {
  let id = UUID()
  var text: String
}
