import SwiftUI

/// Status as a menu button: the current value is the label, the choices check-mark it.
struct DetailStatusMenu<Status: RecordStatus>: View {
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
        Image(systemName: "chevron.down")
          .font(.caption.weight(.semibold))
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, minHeight: 36)
    }
    .glassButton()
    .accessibilityLabel("Status")
    .accessibilityValue(Status.label(for: current))
    .accessibilityIdentifier("detail.status")
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
