import SwiftUI
import UIKit

/// "Colors used" on a coloring page: the symbol key the user is coloring from.
struct ColorKeysSection: View {
  @Environment(\.accountEmail) private var accountEmail
  @Environment(\.connectionAvailable) private var connectionAvailable
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(FormDrawer.self) private var formDrawer
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.theme) private var theme
  @ScaledMetric(relativeTo: .title) private var symbolSize: CGFloat = 40

  @State private var model: ColorKeysModel
  @State private var sheet: ColorKeySheet?
  @State private var copyCount = 0
  /// Prefills a symbol request, such as "Book · Page 3".
  let bookLabel: String

  init(library: LibrarySession, pageID: String, bookLabel: String) {
    _model = State(initialValue: ColorKeysModel(library: library, pageID: pageID))
    self.bookLabel = bookLabel
  }

  var body: some View {
    // The section lives in a lazy stack, so load once rather than on every scroll back.
    content
      .environment(\.symbolRequestThumbnails, requestThumbnails)
      .task { if model.loadState == .idle { await model.load() } }
  }

  private var requestThumbnails: [String: URL] {
    model.requests.compactMapValues { request in
      protectedFiles?.url(collection: SymbolRequestRecord.collection, recordID: request.id,
        filename: request.photo, thumb: "96x96f")
    }
  }

  private var requester: SymbolRequester {
    SymbolRequester(bookLabel: bookLabel, email: accountEmail, send: model.sendRequest)
  }

  @ViewBuilder
  private var content: some View {
    if model.loadState != .unavailable {
      section
    }
  }

  private var section: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      switch model.loadState {
      case .idle where model.keys.isEmpty, .loading where model.keys.isEmpty:
        ProgressView("Loading colors…")
          .frame(maxWidth: .infinity, alignment: .leading)
      default:
        if model.loadState == .failed {
          AccessibleErrorLabel(message: "Couldn’t load colors.")
          Button("Try again") { Task { await model.load() } }
            .accessibilityIdentifier("colorKeys.retry")
        }
        if !model.keys.isEmpty {
          rows
          if let message = model.reorderError { AccessibleErrorLabel(message: message) }
        } else if model.loadState != .failed {
          emptyState
        }
      }
      NeedsConnectionHint()
    }
    .sheet(item: $sheet) { sheet in
      sheetContent(sheet)
        .environment(\.connectionAvailable, connectionAvailable)
        .environment(\.symbolRequestThumbnails, requestThumbnails)
    }
    .sensoryFeedback(.success, trigger: copyCount)
  }

  private var header: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
    return layout {
      Text("Colors used")
        .font(.karla(.title3).weight(.semibold))
        .foregroundStyle(theme.foreground)
        .accessibilityAddTraits(.isHeader)
      if !dynamicTypeSize.isAccessibilitySize { Spacer() }
      if !model.keys.isEmpty {
        Button("Copy", systemImage: "doc.on.doc") {
          UIPasteboard.general.string = model.copyText()
          copyCount += 1
          AccessibilityNotification.Announcement("Copied colors").post()
        }
        .frame(minHeight: 44)
        .accessibilityLabel("Copy colors")
        .accessibilityIdentifier("colorKeys.copy")
        Button("Add symbol", systemImage: "plus") {
          sheet = .picker(position: model.nextPosition)
        }
        .frame(minHeight: 44)
        .disabledWhileFormPresented(formDrawer, or: !connectionAvailable || model.isSaving)
        .accessibilityIdentifier("colorKeys.add")
        if model.keys.count > 1 {
          Button("Reorder", systemImage: "arrow.up.arrow.down") {
            formDrawer.present(detents: [.medium, .large]) { ColorKeyReorderPanel(model: model) }
          }
          .frame(minHeight: 44)
          .disabledWhileFormPresented(formDrawer, or: !connectionAvailable || model.isSaving)
          .accessibilityIdentifier("colorKeys.reorder")
        }
      }
    }
    .font(.karla(.body))
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label("No colors yet", systemImage: "paintpalette")
    } description: {
      Text("Set up the symbols on this page, then add the color you used for each.")
    } actions: {
      Button("Set up symbols") { sheet = .setup }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("colorKeys.setup")
      Button("Add one symbol") { sheet = .picker(position: model.nextPosition) }
        .accessibilityIdentifier("colorKeys.addFirst")
    }
    .disabled(!connectionAvailable || model.isSaving)
    .frame(maxWidth: .infinity)
  }

  private var rows: some View {
    VStack(spacing: 0) {
      ForEach(model.keys) { key in
        Button {
          sheet = .entry(key.write, id: key.id)
        } label: {
          ColorKeyRow(key: key, symbolSize: symbolSize)
        }
        .buttonStyle(.plain)
        // An editor opened mid-reorder would hold the row's old position.
        .disabledWhileFormPresented(formDrawer, or: model.isSaving)
        .accessibilityHint("Edit color")
        .accessibilityIdentifier("colorKeys.row.\(key.position)")
        if key.id != model.keys.last?.id { Divider() }
      }
    }
    .padding(.horizontal, 16)
    .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
  }

  @ViewBuilder
  private func sheetContent(_ sheet: ColorKeySheet) -> some View {
    switch sheet {
    case .setup:
      ColorKeySetupSheet(recentSymbols: model.recentSymbols, requester: requester,
        hasSavedKeys: !model.keys.isEmpty) {
        symbols in await model.setUp(symbols: symbols)
      }
      .task { await model.loadHistoryIfNeeded() }
    case .picker(let position):
      NavigationStack {
        SymbolPickerView(recentSymbols: model.recentSymbols, requester: requester) { symbol in
          self.sheet = .entry(model.newKey(symbol: symbol, position: position), id: nil)
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel) { self.sheet = nil }
          }
        }
      }
      .task { await model.loadHistoryIfNeeded() }
    case .entry(let write, let id):
      ColorKeyEntrySheet(model: model, initial: write, id: id, requester: requester) { saved, advance in
        guard advance else { return self.sheet = nil }
        if let next = model.key(after: saved) {
          self.sheet = .entry(next.write, id: next.id)
        } else {
          self.sheet = .picker(position: model.nextPosition)
        }
      }
      .task { await model.loadHistoryIfNeeded() }
    }
  }
}

enum ColorKeySheet: Identifiable {
  case setup
  case picker(position: Int)
  case entry(ColorKeyWrite, id: String?)

  var id: String {
    switch self {
    case .setup: "setup"
    case .picker(let position): "picker-\(position)"
    case .entry(let write, let id): "entry-\(id ?? "new-\(write.position)")"
    }
  }
}

/// "Reorder": the page's colors with system drag handles. The order saves when the panel closes.
struct ColorKeyReorderPanel: View {
  @Environment(FormDrawer.self) private var formDrawer
  @Environment(\.theme) private var theme
  @ScaledMetric(relativeTo: .title) private var symbolSize: CGFloat = 32

  let model: ColorKeysModel
  @State private var order: [ColorKeyRecord]

  init(model: ColorKeysModel) {
    self.model = model
    _order = State(initialValue: model.keys)
  }

  var body: some View {
    NavigationStack {
      List {
        ForEach(order) { key in
          ColorKeyRow(key: key, symbolSize: symbolSize)
            .accessibilityIdentifier("colorKeys.reorder.\(key.id)")
        }
        .onMove { order.move(fromOffsets: $0, toOffset: $1) }
        .listRowBackground(theme.card)
      }
      .environment(\.editMode, .constant(.active))
      .scrollContentBackground(.hidden)
      .background(theme.themedBackground.ignoresSafeArea())
      .navigationTitle("Reorder")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { formDrawer.dismiss() }.accessibilityIdentifier("colorKeys.reorder.done")
        }
      }
    }
    .onDisappear { Task { await model.reorder(order) } }
  }
}

private struct ColorKeyRow: View {
  @Environment(\.theme) private var theme
  let key: ColorKeyRecord
  let symbolSize: CGFloat

  var body: some View {
    HStack(spacing: 14) {
      ColorKeySymbolView(id: key.symbol, size: symbolSize)
      VStack(alignment: .leading, spacing: 2) {
        Text(key.code.isEmpty ? "No code yet" : key.code)
          .font(.karla(.headline))
          .foregroundStyle(key.code.isEmpty ? theme.mutedForeground : theme.foreground)
        if !key.colorName.isEmpty {
          Text(key.colorName)
            .font(.karla(.subheadline))
            .foregroundStyle(theme.mutedForeground)
        }
      }
      Spacer(minLength: 0)
      SwatchDot(hex: key.swatch)
    }
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .contentShape(.rect)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
  }

  private var accessibilityLabel: String {
    let symbol = SymbolCatalog.bundled.accessibilityName(for: key.symbol)
    return [symbol, key.code.isEmpty ? "No code yet" : key.code, key.colorName]
      .filter { !$0.isEmpty }.joined(separator: ", ")
  }
}

struct SwatchDot: View {
  @Environment(\.theme) private var theme
  @ScaledMetric(relativeTo: .body) private var size: CGFloat = 28
  let hex: String

  var body: some View {
    if let color = Color(swatchHex: hex) {
      Circle()
        .fill(color)
        .strokeBorder(theme.mutedForeground.opacity(0.4), lineWidth: 1)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
  }
}

extension Color {
  init?(swatchHex hex: String) {
    guard let parts = ColorKeys.swatchComponents(hex) else { return nil }
    self.init(.sRGB, red: parts.red, green: parts.green, blue: parts.blue)
  }

  /// The `#RRGGBB` form of this color in sRGB.
  var swatchHex: String {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return ColorKeys.swatchHex(red: red, green: green, blue: blue)
  }
}
