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
            DetailSpecStrip(specs: specs)
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
              ForEach(dateRows, id: \.label) { row in
                DetailMetadataRow(label: row.label, value: row.value)
              }
              if !project.tags.isEmpty {
                DetailMetadataRow(label: "Tags", value: project.tags.map(\.name).formatted(.list(type: .and)))
              }
              if let source = sourceURL {
                DetailMetadataRow(label: "Source") {
                  Link(source.host() ?? source.absoluteString, destination: source)
                    .lineLimit(1)
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

      Text(project.title)
        .font(.title2.bold())
        .foregroundStyle(theme.foreground)
        .accessibilityAddTraits(.isHeader)
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
    if let drill = project.drillShape?.nonEmpty {
      let kit = "\(project.kitCategory.lowercased()) kit"
      specs.append(
        DetailSpec(
          title: "Drill", value: drill.capitalized, caption: kit,
          accessibilityValue: "\(drill), \(kit)"))
    }
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

  private var dateRows: [(label: String, value: String)] {
    [
      ("Purchased", project.datePurchased),
      ("Received", project.dateReceived),
      ("Started", project.dateStarted),
      ("Completed", project.dateCompleted),
    ].compactMap { label, value in
      value.flatMap { DetailDateOnly.formatted($0) }.map { (label, $0) }
    }
  }

  private var sourceURL: URL? {
    guard let url = project.sourceURL?.nonEmpty.flatMap(URL.init(string:)),
      ["http", "https"].contains(url.scheme?.lowercased())
    else { return nil }
    return url
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.title3.weight(.semibold))
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

  init(label: String, value: String) where Content == Text {
    self.label = label
    content = Text(value)
  }

  init(label: String, @ViewBuilder content: () -> Content) {
    self.label = label
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
        .accessibilityElement(children: .combine)
        } else {
        LabeledContent {
          content
            .foregroundStyle(theme.foreground)
        } label: {
          labelView
        }
        .accessibilityElement(children: .combine)
      }
    }
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
