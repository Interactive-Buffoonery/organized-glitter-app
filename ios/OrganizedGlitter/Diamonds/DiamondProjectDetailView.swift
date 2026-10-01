import PhotosUI
import SwiftUI
import UIKit

struct DiamondProjectDetailView: View {
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.theme) private var theme

  let project: DiamondProjectRecord
  let model: LibraryItemDetailModel
  @Binding var logEditor: LibraryItemDetailModel?
  let onCollectionChanged: @MainActor @Sendable () async -> Void

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          header
          DetailStatusRecovery(model: model, onCollectionChanged: onCollectionChanged)

          if !specs.isEmpty {
            DetailSpecStrip(
              specs: specs, isDisabled: model.isMutating || model.unresolvedWriteState != nil)
          }

          ProgressNotesSection(
            model: model, onCollectionChanged: onCollectionChanged,
            logEditor: $logEditor,
            onReveal: { proxy.scrollTo($0, anchor: .center) })

          detailSection("Details") {
            DetailMetadataCard {
              if let company = project.expand?.company?.name.nonEmpty {
                DetailMetadataRow(label: "Company", value: company)
              }
              if let artist = project.expand?.artist?.name.nonEmpty {
                DetailMetadataRow(label: "Artist", value: artist)
              }
              DetailMetadataRow(label: "Kit", value: project.kitCategory.capitalized)
              ForEach(dateFields, id: \.field) { row in
                DetailDateRow(
                  label: row.label,
                  value: row.value,
                  isDisabled: model.isMutating || model.unresolvedWriteState != nil
                ) { date in
                  save { await model.setDate(row.field, to: date) }
                }
              }
              if !project.tags.isEmpty {
                DetailMetadataRow(label: "Tags", value: project.tags.map(\.name).formatted(.list(type: .and)))
              }
              if let source = sourceURL {
                DetailMetadataRow(label: "Source") {
                  Link(source.host() ?? source.absoluteString, destination: source)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("detail.diamond.source")
              }
            }

            if let notes = project.generalNotes?.plainTextFromHTML.nonEmpty {
              Text(notes)
                .foregroundStyle(theme.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
            }
          }

          if let errorMessage = model.errorMessage {
            VStack(alignment: .leading, spacing: 12) {
              AccessibleErrorLabel(message: errorMessage)
              Button("Try again") {
                Task { await model.load() }
              }
            }
          }

          if let mutationErrorMessage = model.mutationErrorMessage,
            model.unresolvedWriteState == nil
          {
            AccessibleErrorLabel(message: mutationErrorMessage)
          }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
      }
      .background {
        theme.themedBackground.ignoresSafeArea()
      }
      .refreshable { await model.refresh() }
    }
  }

  private var header: some View {
    VStack(spacing: 8) {
      CoverArtwork(
        item: .diamond(project),
        url: protectedFiles?.artworkURL(for: .diamond(project)),
        maxPixelDimension: 1_200,
        loadedAccessibilityLabel: "Project artwork"
      )
      .frame(width: horizontalSizeClass == .regular ? 300 : 204)
      .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
      .padding(.bottom, 8)
      .photoViewer(opening: coverPhoto)
      .accessibilityIdentifier("detail.hero")

      DetailInlineTitle(
        value: project.title, field: "title", label: "Title", model: model,
        onCollectionChanged: onCollectionChanged)
      if !LibraryItem.diamond(project).subtitle.isEmpty {
        Text(LibraryItem.diamond(project).subtitle)
          .foregroundStyle(theme.pageSecondaryForeground)
      }
      DetailStatusMenu<DiamondStatus>(
        current: project.status, model: model, onCollectionChanged: onCollectionChanged)
      .padding(.top, 4)
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
  }

  private var specs: [DetailSpec] {
    var specs: [DetailSpec] = []
    if let width = project.width, let height = project.height {
      specs.append(
        DetailSpec(
          title: "Size", value: "\(width.formatted())×\(height.formatted())", caption: "cm",
          accessibilityValue: "\(width.formatted()) by \(height.formatted()) centimeters"))
    }
    let drill = project.drillShape?.nonEmpty
    let kit = "\(project.kitCategory.lowercased()) kit"
    specs.append(
      DetailSpec(
        title: "Drill", value: drill?.capitalized ?? "Not set", caption: kit,
        accessibilityValue: "\(drill ?? "Not set"), \(kit)",
        choices: [
          DetailSpec.Choice(
            title: "Drill shape",
            options: [
              .init(value: "", label: "Not set"),
              .init(value: "round", label: "Round"),
              .init(value: "square", label: "Square"),
            ],
            selection: drill ?? ""
          ) { value in
            guard value != (drill ?? "") else { return }
            save { await model.updateFields(["drill_shape": value]) }
          },
          DetailSpec.Choice(
            title: "Kit",
            options: [
              .init(value: "full", label: "Full size"),
              .init(value: "mini", label: "Mini"),
            ],
            selection: project.kitCategory
          ) { value in
            guard value != project.kitCategory else { return }
            save { await model.updateFields(["kit_category": value]) }
          },
        ]))
    if let total = project.totalDiamonds, total > 0 {
      let colors = project.colorCount.flatMap { $0 > 0 ? "\(Int($0)) colors" : nil }
      specs.append(
        DetailSpec(
          title: "Diamonds",
          value: Int(total).formatted(.number.notation(.compactName).precision(.significantDigits(1...3))),
          caption: colors,
          accessibilityValue: [Int(total).formatted(), colors].compactMap { $0 }.joined(separator: ", ")))
    }
    if let started = project.dateStarted.flatMap({ DetailDateOnly.date($0) }),
      let day = project.dateStarted.flatMap({ DetailDateOnly.monthDay($0) })
    {
      let end = project.dateCompleted.flatMap { DetailDateOnly.date($0) } ?? .now
      let elapsed = DetailDateOnly.elapsed(from: started, to: end)
      specs.append(
        DetailSpec(
          title: "Started", value: day, caption: elapsed,
          accessibilityValue: [day, elapsed].compactMap { $0 }.joined(separator: ", ")))
    }
    return specs
  }

  private var dateFields: [(field: String, label: String, value: String?)] {
    [
      ("date_purchased", "Purchased", project.datePurchased),
      ("date_received", "Received", project.dateReceived),
      ("date_started", "Started", project.dateStarted),
      ("date_completed", "Completed", project.dateCompleted),
    ]
  }

  private func save(_ write: @escaping @MainActor () async -> Bool) {
    saveDetailChange(write, onCollectionChanged: onCollectionChanged)
  }

  private var sourceURL: URL? {
    guard let url = project.sourceURL?.nonEmpty.flatMap(URL.init(string:)),
      ["http", "https"].contains(url.scheme?.lowercased())
    else { return nil }
    return url
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.karla(.title3).weight(.semibold))
      .foregroundStyle(theme.foreground)
      .accessibilityAddTraits(.isHeader)
  }

  private var coverPhoto: DetailPhoto? {
    guard let url = protectedFiles?.artworkURL(for: .diamond(project)) else { return nil }
    return DetailPhoto(
      id: "project-cover", url: url, fullSizeURL: url,
      accessibilityLabel: "Project artwork")
  }

  private func detailSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionTitle(title)
      content()
    }
  }
}


/// A date-only field edited in place, committed only after the picker closes.
private struct DetailDateRow: View {
  @Environment(FormDrawer.self) private var formDrawer
  @Environment(\.theme) private var theme
  @State private var isEditingDate = false
  @State private var draftDate = Date.now

  let label: String
  let value: String?
  let isDisabled: Bool
  let onChange: (Date?) -> Void

  var body: some View {
    let storedDate = value.flatMap { DetailDateOnly.date($0) }
    DetailMetadataRow(label: label, combinesChildren: false) {
      HStack(spacing: 0) {
        Button {
          draftDate = storedDate ?? .now
          isEditingDate = true
        } label: {
          if let value, let formatted = DetailDateOnly.formatted(value) {
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
        .accessibilityValue(value.flatMap { DetailDateOnly.formatted($0) } ?? "No date")
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
        DatePicker(label, selection: $draftDate, displayedComponents: .date)
          .datePickerStyle(.graphical)
        HStack {
          Button("Cancel") { isEditingDate = false }
          Spacer()
          Button("Save") {
            guard !formDrawer.isPresenting, !isDisabled else { return }
            isEditingDate = false
            if storedDate.map({ DetailDateOnly.string(from: $0) })
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

struct DetailMetadataCard<Content: View>: View {
  @Environment(\.theme) private var theme
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) {
      content
    }
    .padding(.horizontal, 16)
    .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
  }
}

struct DetailMetadataRow<Content: View>: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.theme) private var theme

  let label: String
  let content: Content
  private var combinesChildren = true

  init(label: String, value: String) where Content == Text {
    self.label = label
    content = Text(value)
  }

  /// Rows holding several controls pass `combinesChildren: false` so each stays reachable.
  init(label: String, combinesChildren: Bool = true, @ViewBuilder content: () -> Content) {
    self.label = label
    self.combinesChildren = combinesChildren
    self.content = content()
  }

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 4) {
          labelView
          content
            .foregroundStyle(theme.foreground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        LabeledContent {
          content
            .foregroundStyle(theme.foreground)
        } label: {
          labelView
        }
      }
    }
    .accessibilityElement(children: combinesChildren ? .combine : .contain)
    .padding(.vertical, 10)
    .frame(minHeight: 44)
    .overlay(alignment: .bottom) {
      Divider()
    }
  }

  private var labelView: some View {
    Text(label)
      .foregroundStyle(theme.pageSecondaryForeground)
  }
}
