import SwiftUI

/// Status as a menu button: the current value is the label, the choices check-mark it.
struct DetailStatusMenu<Status: RecordStatus>: View {
  @Environment(\.colorScheme) private var colorScheme

  let current: String
  let model: LibraryItemDetailModel
  let onCollectionChanged: @MainActor @Sendable () async -> Void

  var body: some View {
    let palette = DetailStatusAppearance.palette(for: current, colorScheme: colorScheme)
    Menu {
      Picker(
        "Status",
        selection: Binding(get: { current }, set: { select($0) })
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
      .foregroundStyle(palette.foreground)
      .padding(.horizontal, 14)
      .padding(.vertical, 7)
      .background(palette.background, in: .capsule)
      .fixedSize(horizontal: false, vertical: true)
      .frame(minHeight: 44)
      .contentShape(.rect)
    }
    .disabled(model.isMutating || model.unresolvedWriteState != nil)
    .accessibilityLabel("Status")
    .accessibilityValue(Status.label(for: current))
    .accessibilityIdentifier("detail.status")
  }

  private func select(_ status: String) {
    Task {
      let changed = await model.setStatus(status)
      if changed || (model.unresolvedStatusWrite && model.unresolvedWriteState == .refreshed) {
        await onCollectionChanged()
      }
    }
  }
}

/// Soft status pairs follow the web app's status color families.
enum DetailStatusAppearance {
  static func palette(
    for status: String, colorScheme: ColorScheme
  ) -> (foreground: Color, background: Color) {
    let (light, lightBackground, dark, darkBackground): (UInt32, UInt32, UInt32, UInt32) =
      switch status {
      case "wishlist", "destashed": (0x9F1239, 0xFFE4E6, 0xFFE4E6, 0x6B2138)
      case "purchased": (0x075985, 0xE0F2FE, 0xD9F2FF, 0x164E63)
      case "stash", "in_stash": (0x9A3412, 0xFFEDD5, 0xFFEDD5, 0x7C2D12)
      case "kitted": (0x115E59, 0xCCFBF1, 0xCCFBF1, 0x134E4A)
      case "progress", "in_progress": (0x6B21A8, 0xEAD7FF, 0xF3E8FF, 0x581C87)
      case "onhold": (0x92400E, 0xFEF3C7, 0xFEF3C7, 0x78350F)
      case "completed": (0x065F46, 0xD1FAE5, 0xD1FAE5, 0x064E3B)
      default: (0x374151, 0xE5E7EB, 0xE5E7EB, 0x374151)
      }
    return colorScheme == .dark
      ? (Color(hex: dark), Color(hex: darkBackground))
      : (Color(hex: light), Color(hex: lightBackground))
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
