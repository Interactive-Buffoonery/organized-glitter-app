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
  let onCollectionChanged: @MainActor @Sendable () async -> Void

  @State private var isAddingNote = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header
        actions

        if !specs.isEmpty {
          DetailSpecStrip(specs: specs)
        }

        VStack(alignment: .leading, spacing: 12) {
          sectionTitle("Progress")
          if progressPhotos.isEmpty {
            ContentUnavailableView(
              "No progress photos",
              systemImage: "photo.on.rectangle",
              description: Text("Log a dated photo as your project changes.")
            )
            .frame(maxWidth: .infinity)
          } else {
            DetailPhotoContactSheet(photos: progressPhotos)
          }

          if !isAddingNote {
            unresolvedWriteRecovery
          }
        }

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

        if !model.progressNotes.isEmpty {
          detailSection("Progress notes") {
            ForEach(model.progressNotes) { note in
              VStack(alignment: .leading, spacing: 6) {
                Text(noteDate(note.date))
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(theme.pageSecondaryForeground)
                if let content = note.content.nonEmpty {
                  Text(content)
                    .foregroundStyle(theme.foreground)
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(14)
              .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
            }

            if model.canLoadMoreProgressNotes {
              Button("Load more notes") {
                Task { await model.loadMoreProgressNotes() }
              }
              .disabled(model.isLoadingMore)
              .frame(maxWidth: .infinity)
            }
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
          !isAddingNote, model.unresolvedWriteState == nil
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
    .refreshable { await model.load() }
    .sheet(isPresented: $isAddingNote) {
      DiamondProgressNoteEditor(
        model: model,
        onCollectionChanged: onCollectionChanged
      )
    }
  }

  private var progressPhotos: [DetailPhoto] {
    model.progressNotes.compactMap { note in
      guard let image = note.image?.nonEmpty,
        let url = protectedFiles?.url(
          collection: "progress_notes", recordID: note.id, filename: image,
          thumb: ArtworkThumb.gallery)
      else { return nil }
      return DetailPhoto(
        id: note.id,
        url: url,
        accessibilityLabel: progressPhotoLabel(for: note)
      )
    }
  }

  @ViewBuilder
  private var unresolvedWriteRecovery: some View {
    switch model.unresolvedWriteState {
    case .needsRefresh:
      if let message = model.mutationErrorMessage {
        AccessibleErrorLabel(message: message)
      }
      Button("Refresh status") {
        Task {
          if await model.refreshUnresolvedWriteStatus() {
            await onCollectionChanged()
          }
        }
      }
      .buttonStyle(.bordered)
      .disabled(model.isMutating)
      .accessibilityIdentifier("detail.diamond.noteRefresh")
    case .refreshed:
      if let message = model.mutationErrorMessage {
        Label(message, systemImage: "checkmark.circle")
          .foregroundStyle(theme.foreground)
      }
      Button("Done reviewing progress notes") {
        model.clearUnresolvedWriteRecovery()
      }
      .buttonStyle(.bordered)
    case nil:
      EmptyView()
    }
  }

  private var header: some View {
    VStack(spacing: 8) {
      CoverArtwork(
        item: .diamond(project),
        url: LibraryItem.diamond(project).artworkURL(
          using: model.client, token: protectedFiles?.token),
        maxPixelDimension: 1_200,
        loadedAccessibilityLabel: "Project artwork"
      )
      .frame(width: horizontalSizeClass == .regular ? 320 : 260)
      .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
      .padding(.bottom, 8)
      .accessibilityIdentifier("detail.hero")

      Text(project.title)
        .font(.title2.bold())
        .foregroundStyle(theme.foreground)
        .accessibilityAddTraits(.isHeader)
      if !LibraryItem.diamond(project).subtitle.isEmpty {
        Text(LibraryItem.diamond(project).subtitle)
          .foregroundStyle(theme.pageSecondaryForeground)
      }
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
  }

  private var actions: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: 10))
      : AnyLayout(HStackLayout(spacing: 12))
    return layout {
      DetailStatusMenu<DiamondStatus>(current: project.status) { status in
        Task {
          if await model.setStatus(status) {
            await onCollectionChanged()
          }
        }
      }
      .disabled(model.isMutating || model.unresolvedWriteState != nil)

      Button {
        isAddingNote = true
      } label: {
        Label("Log", systemImage: "pencil")
          .frame(maxWidth: .infinity, minHeight: 36)
      }
      .glassProminentButton()
      .foregroundStyle(theme.primaryForeground)
      .disabled(model.isMutating || model.unresolvedWriteState != nil)
      .accessibilityLabel("Log progress")
      .accessibilityIdentifier("detail.diamond.addNote")
    }
    .controlSize(.large)
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

  private func noteDate(_ value: String) -> String {
    DetailDateOnly.formatted(value) ?? value
  }

  private func progressPhotoLabel(for note: DiamondProgressNoteRecord) -> String {
    let base = "Progress photo from \(noteDate(note.date))"
    let caption = note.content
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return caption.isEmpty ? base : "\(base): \(caption)"
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

struct DiamondProgressNoteEditor: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme

  let model: LibraryItemDetailModel
  let onCollectionChanged: @MainActor @Sendable () async -> Void

  @State private var date = Date()
  @State private var content = ""
  @State private var selectedItem: PhotosPickerItem?
  @State private var processedPhoto: ProcessedDetailPhoto?
  @State private var previewImage: UIImage?
  @State private var isPreparingPhoto = false
  @State private var photoErrorMessage: String?

  var body: some View {
    let photoPickerTitle =
      processedPhoto == nil ? "Choose photo" : "Choose a different photo"

    NavigationStack {
      Form {
        Group {
          Section("Progress") {
            DatePicker("Date", selection: $date, displayedComponents: .date)
            TextField("Caption (optional)", text: $content, axis: .vertical)
              .lineLimit(3...8)
            Text("Add a photo, a caption, or both.")
              .font(.footnote)
              .foregroundStyle(theme.pageSecondaryForeground)
          }
          .disabled(model.unresolvedWriteState != nil)

          Section("Photo") {
            if let previewImage {
              Image(uiImage: previewImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 320)
                .accessibilityLabel("Selected progress photo")
                .accessibilityIdentifier("detail.diamond.notePhoto")
            }

            PhotosPicker(selection: $selectedItem, matching: .images) {
              Label(
                photoPickerTitle,
                systemImage: "photo.on.rectangle"
              )
            }
            .disabled(isPreparingPhoto || model.isMutating)
          }
          .disabled(model.unresolvedWriteState != nil)

          if isPreparingPhoto {
            Section {
              ProgressView("Preparing photo…")
            }
          } else if model.isMutating {
            Section {
              ProgressView(
                model.unresolvedWriteState == nil
                  ? (processedPhoto == nil ? "Adding progress note…" : "Uploading photo…")
                  : "Checking save status…"
              )
            }
          }

          if let message = photoErrorMessage {
            Section {
              AccessibleErrorLabel(message: message)
            }
          } else if let message = model.mutationErrorMessage {
            Section {
              if model.unresolvedWriteState == .refreshed {
                Label(message, systemImage: "checkmark.circle")
                  .foregroundStyle(theme.foreground)
              } else {
                AccessibleErrorLabel(message: message)
              }
            }
          }
        }
        .listRowBackground(theme.card)
      }
      .themedScrollBackground()
      .navigationTitle("Add progress note")
      .navigationBarTitleDisplayMode(.inline)
      .interactiveDismissDisabled(model.isMutating)
      .accessibilityIdentifier("detail.diamond.noteEditor")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .disabled(model.isMutating)
        }
        ToolbarItem(placement: .confirmationAction) {
          switch model.unresolvedWriteState {
          case .needsRefresh:
            Button("Refresh status") {
              Task { await refreshUploadStatus() }
            }
            .disabled(model.isMutating)
            .accessibilityIdentifier("detail.diamond.noteRefresh")
          case .refreshed:
            Button("Back to project") {
              model.clearUnresolvedWriteRecovery()
              dismiss()
            }
            .accessibilityIdentifier("detail.diamond.noteReview")
          case nil:
            Button(model.mutationErrorMessage == nil ? "Add" : "Try again") {
              Task { await submit() }
            }
            .disabled(!canSubmit || isPreparingPhoto || model.isMutating)
            .accessibilityIdentifier(
              model.mutationErrorMessage == nil
                ? "detail.diamond.noteSubmit" : "detail.diamond.noteRetry"
            )
          }
        }
      }
      .task(id: selectedItem) {
        await prepareSelectedPhoto()
      }
    }
  }

  private var canSubmit: Bool {
    photoErrorMessage == nil
      && (processedPhoto != nil || !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  private func prepareSelectedPhoto() async {
    guard let selectedItem else { return }
    isPreparingPhoto = true
    photoErrorMessage = nil
    model.mutationErrorMessage = nil
    processedPhoto = nil
    previewImage = nil
    AccessibilityNotification.Announcement("Preparing photo").post()
    defer { isPreparingPhoto = false }
    do {
      let photo = try await DetailPhotoProcessor.process(
        item: selectedItem
      )
      try Task.checkCancellation()
      processedPhoto = photo
      previewImage = await Task.detached(priority: .userInitiated) {
        UIImage(data: photo.data)
      }.value
    } catch is CancellationError {
      return
    } catch let error as DetailPhotoProcessingError {
      photoErrorMessage = error.message
      self.selectedItem = nil
    } catch {
      photoErrorMessage = "That photo could not be prepared. Try another image."
      self.selectedItem = nil
    }
  }

  private func submit() async {
    guard canSubmit else { return }
    AccessibilityNotification.Announcement(
      processedPhoto == nil ? "Adding progress note" : "Uploading photo"
    ).post()
    if await model.addDiamondProgressNote(content: content, date: date, photo: processedPhoto) {
      await onCollectionChanged()
      AccessibilityNotification.Announcement(
        processedPhoto == nil ? "Progress note added" : "Photo added"
      ).post()
      dismiss()
    } else if model.unresolvedWriteState == .refreshed {
      AccessibilityNotification.Announcement(
        processedPhoto == nil
          ? "Progress notes refreshed. Review them before adding another note."
          : "Progress notes and photos refreshed. Review them before adding another note."
      ).post()
    }
  }

  private func refreshUploadStatus() async {
    AccessibilityNotification.Announcement("Refreshing progress note status").post()
    if await model.refreshUnresolvedWriteStatus() {
      await onCollectionChanged()
      AccessibilityNotification.Announcement(
        processedPhoto == nil ? "Progress notes refreshed" : "Progress notes and photos refreshed"
      ).post()
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
