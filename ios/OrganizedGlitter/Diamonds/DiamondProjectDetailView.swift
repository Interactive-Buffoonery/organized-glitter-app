import PhotosUI
import SwiftUI
import UIKit

struct DiamondProjectDetailView: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.theme) private var theme

  let project: DiamondProjectRecord
  let model: LibraryItemDetailModel
  let onCollectionChanged: @MainActor @Sendable () async -> Void

  @State private var isAddingNote = false

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        RecordArtwork(
          url: LibraryItem.diamond(project).artworkURL(using: model.client),
          maxHeight: heroHeight,
          emptyMinHeight: 180,
          successAccessibilityLabel: "Project artwork"
        )
        .frame(maxWidth: .infinity, maxHeight: heroHeight)
        .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
        .clipShape(.rect(cornerRadius: Theme.Radius.medium))
        .accessibilityIdentifier("detail.hero")

        VStack(alignment: .leading, spacing: 6) {
          Text(project.title)
            .font(.title2.bold())
            .foregroundStyle(theme.foreground)
            .accessibilityAddTraits(.isHeader)
          if !LibraryItem.diamond(project).subtitle.isEmpty {
            Text(LibraryItem.diamond(project).subtitle)
              .font(.body)
              .foregroundStyle(theme.pageSecondaryForeground)
          }
        }

        DetailMetadataCard {
          DetailMetadataRow(label: "Status") {
            StatusBadge(status: project.status, presentation: .quiet)
          }
          if let width = project.width, let height = project.height {
            DetailMetadataRow(
              label: "Size",
              value: "\(width.formatted()) × \(height.formatted()) cm"
            )
          }
          DetailMetadataRow(
            label: "Drills",
            value: project.drillShape?.nonEmpty?.organizedGlitterLabel ?? "Not set"
          )
        }

        detailSection("Photos") {
          if progressPhotos.isEmpty {
            ContentUnavailableView(
              "No progress photos",
              systemImage: "photo.on.rectangle",
              description: Text("Add a dated photo as your project changes.")
            )
            .frame(maxWidth: .infinity)
          } else {
            DetailPhotoGallery(photos: progressPhotos)
          }

          Button {
            isAddingNote = true
          } label: {
            Label("Add photo", systemImage: "plus")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .disabled(model.isMutating || model.unresolvedWriteState != nil)
          .accessibilityIdentifier("detail.diamond.addNote")

          if !isAddingNote {
            unresolvedWriteRecovery
          }
        }

        detailSection("Project details") {
          DetailMetadataCard {
            DetailMetadataRow(
              label: "Kit",
              value: project.kitCategory.organizedGlitterLabel
            )
          }

          if let notes = project.generalNotes?.nonEmpty {
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

        if let mutationErrorMessage = model.mutationErrorMessage, !isAddingNote {
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
      guard let image = note.image?.nonEmpty else { return nil }
      return DetailPhoto(
        id: note.id,
        url: model.client.fileURL(
          collection: "progress_notes",
          recordID: note.id,
          filename: image
        ),
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

  private var heroHeight: CGFloat {
    horizontalSizeClass == .regular ? 360 : 250
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
      Text(title)
        .font(.title3.weight(.semibold))
        .foregroundStyle(theme.foreground)
        .accessibilityAddTraits(.isHeader)
      content()
    }
  }
}

private struct DiamondProgressNoteEditor: View {
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
        Section("Progress") {
          DatePicker("Date", selection: $date, displayedComponents: .date)
          TextField("Caption (optional)", text: $content, axis: .vertical)
            .lineLimit(3...8)
        }
        .listRowBackground(theme.card)
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
        .listRowBackground(theme.card)
        .disabled(model.unresolvedWriteState != nil)

        if isPreparingPhoto {
          Section {
            ProgressView("Preparing photo…")
          }
          .listRowBackground(theme.card)
        } else if model.isMutating {
          Section {
            ProgressView(
              model.unresolvedWriteState == nil
                ? (processedPhoto == nil ? "Adding progress note…" : "Uploading photo…")
                : "Checking save status…"
            )
          }
          .listRowBackground(theme.card)
        }

        if let message = photoErrorMessage {
          Section {
            AccessibleErrorLabel(message: message)
          }
          .listRowBackground(theme.card)
        } else if let message = model.mutationErrorMessage {
          Section {
            if model.unresolvedWriteState == .refreshed {
              Label(message, systemImage: "checkmark.circle")
                .foregroundStyle(theme.foreground)
            } else {
              AccessibleErrorLabel(message: message)
            }
          }
          .listRowBackground(theme.card)
        }
      }
      .themedScrollBackground()
      .navigationTitle("Add progress note")
      .navigationBarTitleDisplayMode(.inline)
      .interactiveDismissDisabled(isPreparingPhoto || model.isMutating)
      .accessibilityIdentifier("detail.diamond.noteEditor")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .disabled(isPreparingPhoto || model.isMutating)
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
      guard let data = try await selectedItem.loadTransferable(type: Data.self) else {
        throw DetailPhotoProcessingError.unsupportedImage
      }
      try Task.checkCancellation()
      let photo = try await DetailPhotoProcessor.process(
        data: data,
        contentTypeIdentifier: selectedItem.supportedContentTypes.first?.identifier
      )
      try Task.checkCancellation()
      processedPhoto = photo
      previewImage = UIImage(data: photo.data)
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
    LabeledContent {
      content
        .foregroundStyle(theme.foreground)
    } label: {
      Text(label)
        .foregroundStyle(theme.pageSecondaryForeground)
    }
    .padding(.vertical, 10)
    .frame(minHeight: 44)
    .overlay(alignment: .bottom) {
      Divider()
    }
  }
}
