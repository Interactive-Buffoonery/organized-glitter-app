import SwiftUI

/// Status as a menu button: the current value is the label, the choices check-mark it.
struct DetailStatusMenu<Status: RecordStatus>: View {
  @Environment(\.colorScheme) private var colorScheme

  let current: String
  let onSelect: (String) -> Void

  var body: some View {
    Menu {
      Picker(
        "Status",
        selection: Binding(get: { current }, set: { onSelect($0) })
      ) {
        ForEach(Status.allCases, id: \.rawValue) { status in
          Label(status.label, systemImage: status.systemImage)
            .tag(status.rawValue)
        }
      }
    } label: {
      HStack(spacing: 6) {
        Label(Status.label(for: current), systemImage: Status.systemImage(for: current))
          .labelStyle(.titleAndIcon)
        Image(systemName: "chevron.down")
          .font(.caption.weight(.semibold))
          .accessibilityHidden(true)
      }
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(DetailStatusAppearance.foreground(for: current, colorScheme: colorScheme))
      .padding(.horizontal, 14)
      .padding(.vertical, 7)
      .background(
        DetailStatusAppearance.background(for: current, colorScheme: colorScheme),
        in: .capsule
      )
      .fixedSize(horizontal: false, vertical: true)
      .frame(minHeight: 44)
      .contentShape(.rect)
    }
    .accessibilityLabel("Status")
    .accessibilityValue(Status.label(for: current))
    .accessibilityIdentifier("detail.status")
  }
}

/// Soft status pairs follow the web app's status color families.
enum DetailStatusAppearance {
  static func foreground(for status: String, colorScheme: ColorScheme) -> Color {
    let dark = colorScheme == .dark
    switch status {
    case "wishlist", "destashed": Color(hex: dark ? 0xFFE4E6 : 0x9F1239)
    case "purchased": Color(hex: dark ? 0xD9F2FF : 0x075985)
    case "stash", "in_stash": Color(hex: dark ? 0xFFEDD5 : 0x9A3412)
    case "kitted": Color(hex: dark ? 0xCCFBF1 : 0x115E59)
    case "progress", "in_progress": Color(hex: dark ? 0xF3E8FF : 0x6B21A8)
    case "onhold": Color(hex: dark ? 0xFEF3C7 : 0x92400E)
    case "completed": Color(hex: dark ? 0xD1FAE5 : 0x065F46)
    default: Color(hex: dark ? 0xE5E7EB : 0x374151)
    }
  }

  static func background(for status: String, colorScheme: ColorScheme) -> Color {
    let dark = colorScheme == .dark
    switch status {
    case "wishlist", "destashed": Color(hex: dark ? 0x6B2138 : 0xFFE4E6)
    case "purchased": Color(hex: dark ? 0x164E63 : 0xE0F2FE)
    case "stash", "in_stash": Color(hex: dark ? 0x7C2D12 : 0xFFEDD5)
    case "kitted": Color(hex: dark ? 0x134E4A : 0xCCFBF1)
    case "progress", "in_progress": Color(hex: dark ? 0x581C87 : 0xEAD7FF)
    case "onhold": Color(hex: dark ? 0x78350F : 0xFEF3C7)
    case "completed": Color(hex: dark ? 0x064E3B : 0xD1FAE5)
    default: Color(hex: dark ? 0x374151 : 0xE5E7EB)
    }
  }
}

struct DetailStatusRecovery: View {
  let model: LibraryItemDetailModel
  let onCollectionChanged: @MainActor @Sendable () async -> Void

  var body: some View {
    if let message = model.statusErrorMessage {
      AccessibleErrorLabel(message: message)
    }
    if model.unresolvedStatusWrite {
      VStack(alignment: .leading, spacing: 8) {
        if let message = model.mutationErrorMessage {
          AccessibleErrorLabel(message: message)
        }
        switch model.unresolvedWriteState {
        case .needsRefresh:
          Button("Refresh status") {
            Task {
              if await model.refreshUnresolvedWriteStatus() {
                await onCollectionChanged()
              }
            }
          }
          .disabled(model.isMutating)
          .accessibilityIdentifier("detail.status.refresh")
        case .refreshed:
          Button("Done reviewing status") {
            model.clearUnresolvedWriteRecovery()
          }
          .accessibilityIdentifier("detail.status.reviewed")
        case nil:
          EmptyView()
        }
      }
      .buttonStyle(.bordered)
    }
  }
}

struct DetailSpec: Identifiable {
  let title: String
  let value: String
  let caption: String?
  let accessibilityValue: String

  var id: String { title }
}

/// App Store-style info row. Falls back to labeled rows at accessibility sizes.
struct DetailSpecStrip: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.theme) private var theme

  let specs: [DetailSpec]

  var body: some View {
    if dynamicTypeSize.isAccessibilitySize {
      DetailMetadataCard {
        ForEach(specs) { spec in
          DetailMetadataRow(
            label: spec.title.capitalized,
            value: [spec.value, spec.caption].compactMap { $0 }.joined(separator: ", "))
        }
      }
      .accessibilityIdentifier("detail.specs")
    } else {
      HStack(alignment: .top, spacing: 0) {
        ForEach(Array(specs.enumerated()), id: \.element.id) { index, spec in
          if index > 0 {
            Divider().frame(height: 44)
          }
          VStack(spacing: 2) {
            Text(spec.title.uppercased())
              .font(.caption2.weight(.medium))
              .foregroundStyle(theme.pageSecondaryForeground)
            Text(spec.value)
              .font(.headline)
              .foregroundStyle(theme.foreground)
            if let caption = spec.caption {
              Text(caption)
                .font(.caption2)
                .foregroundStyle(theme.pageSecondaryForeground)
            }
          }
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .frame(maxWidth: .infinity)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(spec.title.capitalized)
          .accessibilityValue(spec.accessibilityValue)
        }
      }
      .padding(.vertical, 12)
      .overlay(alignment: .top) { Divider() }
      .overlay(alignment: .bottom) { Divider() }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("detail.specs")
    }
  }
}
