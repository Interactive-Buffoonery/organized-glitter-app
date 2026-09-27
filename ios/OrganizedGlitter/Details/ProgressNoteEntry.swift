import PhotosUI
import SwiftUI
import UIKit

struct ProgressNoteEntry: View {
  @Environment(\.photoViewer) private var viewer
  @Environment(\.theme) private var theme

  let note: ProgressNoteItem
  let photoURL: URL?
  var onOpenPhoto: (() -> Void)? = nil
  var onSave: ((_ content: String, _ date: Date) async -> String?)? = nil
  var onDelete: (() async -> String?)? = nil
  var actionsDisabled = false

  @State private var isEditing = false
  @State private var draftContent = ""
  @State private var draftDate = Date()
  @State private var isSaving = false
  @State private var showsDeleteConfirmation = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top) {
        Label(formattedDate, systemImage: "calendar")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(theme.pageSecondaryForeground)
          .accessibilityLabel("Progress logged \(formattedDate)")
        Spacer(minLength: 8)
        if !isEditing, onSave != nil || onDelete != nil {
          Menu {
            if onSave != nil {
              Button("Edit note", systemImage: "pencil") { beginEditing() }
            }
            if onDelete != nil {
              Button(deleteTitle, systemImage: "trash", role: .destructive) {
                showsDeleteConfirmation = true
              }
            }
          } label: {
            Image(systemName: "ellipsis")
              .frame(width: 44, height: 44)
              .contentShape(.rect)
          }
          .accessibilityLabel("Actions for progress note from \(formattedDate)")
          .disabled(actionsDisabled || isSaving)
        }
      }

      if let photoURL {
        let photo = notePhoto(url: photoURL)
        if let onOpenPhoto {
          Button(action: onOpenPhoto) { photo }
            .buttonStyle(.plain)
            .accessibilityLabel("Open progress photo from \(formattedDate)")
        } else if let viewer {
          Button { viewer.open(note.id) } label: { photo }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: note.id, in: viewer.namespace)
            .accessibilityLabel("Open progress photo from \(formattedDate)")
        } else {
          photo
        }
      }

      if isEditing {
        DatePicker("Date", selection: $draftDate, displayedComponents: .date)
        TextField("Caption", text: $draftContent, axis: .vertical)
          .lineLimit(3...8)
          .accessibilityIdentifier("progressNote.captionEditor")
        HStack {
          Button("Cancel") { isEditing = false; errorMessage = nil }
            .disabled(isSaving)
          Spacer()
          Button(isSaving ? "Saving…" : "Save") {
            Task { await save() }
          }
          .buttonStyle(.borderedProminent)
          .disabled(isSaving || actionsDisabled || !canSave)
          .accessibilityIdentifier("progressNote.save")
        }
      } else if let content = note.content.nonEmpty {
        Text(renderedCaption(content))
          .font(.body)
          .foregroundStyle(theme.foreground)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("progressNote.caption")
      }

      if let errorMessage {
        AccessibleErrorLabel(message: errorMessage)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
    .confirmationDialog(
      deleteTitle,
      isPresented: $showsDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button(deleteTitle, role: .destructive) { Task { await delete() } }
    } message: {
      Text("This progress note will be removed from your account.")
    }
  }

  private var formattedDate: String {
    DetailDateOnly.formatted(note.date) ?? note.date
  }

  private var deleteTitle: String {
    note.image?.nonEmpty == nil ? "Delete note" : "Delete note and photo"
  }

  private var canSave: Bool {
    note.image?.nonEmpty != nil
      || !draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func notePhoto(url: URL) -> some View {
    RemoteArtwork(url: url, maxPixelDimension: 1_200) { phase in
      switch phase {
      case .success(let image):
        image.resizable().scaledToFit()
          .frame(maxWidth: .infinity)
          .accessibilityLabel("Progress photo from \(formattedDate)")
      case .failure:
        photoPlaceholder("Photo unavailable", systemImage: "photo.badge.exclamationmark")
          .aspectRatio(4 / 5, contentMode: .fit)
      case .empty:
        photoPlaceholder("Loading photo", systemImage: "photo")
          .aspectRatio(4 / 5, contentMode: .fit)
          .overlay { ProgressView().accessibilityHidden(true) }
      @unknown default:
        photoPlaceholder("Photo unavailable", systemImage: "photo")
          .aspectRatio(4 / 5, contentMode: .fit)
      }
    }
    .frame(maxWidth: .infinity)
    .background(theme.muted.opacity(0.45))
    .clipShape(.rect(cornerRadius: Theme.Radius.medium))
  }

  private func photoPlaceholder(_ title: String, systemImage: String) -> some View {
    Label(title, systemImage: systemImage)
      .foregroundStyle(theme.mutedForeground)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func beginEditing() {
    draftContent = note.content
    draftDate = DetailDateOnly.date(note.date) ?? .now
    errorMessage = nil
    isEditing = true
  }

  private func save() async {
    guard let onSave else { return }
    isSaving = true
    defer { isSaving = false }
    errorMessage = await onSave(draftContent, draftDate)
    if errorMessage == nil { isEditing = false }
  }

  private func delete() async {
    guard let onDelete else { return }
    isSaving = true
    defer { isSaving = false }
    errorMessage = await onDelete()
  }

  private func renderedCaption(_ caption: String) -> AttributedString {
    (try? AttributedString(markdown: caption, options: .init(interpretedSyntax: .full)))
      ?? AttributedString(caption)
  }
}

struct ProgressNotesSection: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.theme) private var theme

  let model: LibraryItemDetailModel
  let onCollectionChanged: @MainActor @Sendable () async -> Void
  @Binding var logEditor: LibraryItemDetailModel?
  var onOpenPhoto: ((ProgressNoteItem) -> Void)? = nil
  var onReveal: ((String) -> Void)? = nil

  @State private var isAddingNote = false
  @State private var revealedNoteID: String?
  @State private var highlightedNoteID: String?

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 12) {
        header
        if model.progressNotes.isEmpty {
          ContentUnavailableView(
            "No progress notes", systemImage: "note.text",
            description: Text("Log a photo, a caption, or both as your work changes."))
            .frame(maxWidth: .infinity)
        } else {
          LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(model.progressNotes) { note in
              ProgressNoteEntry(
                note: note,
                photoURL: protectedFiles?.photoURL(for: note, thumb: ArtworkThumb.gallery),
                onOpenPhoto: onOpenPhoto.map { open in { open(note) } },
                onSave: { content, date in
                  let error = await model.updateProgressNote(note, content: content, date: date)
                  if error == nil { await onCollectionChanged() }
                  return error
                },
                onDelete: {
                  let error = await model.deleteProgressNote(note)
                  if error == nil { await onCollectionChanged() }
                  return error
                },
                actionsDisabled: model.isMutating || model.unresolvedWriteState != nil
              )
              .savedEntryReveal(
                isPending: note.recordID == pendingNoteID,
                isHighlighted: note.recordID == highlightedNoteID)
              .id("note-\(note.recordID)")
            }
          }
        }
        if model.canLoadMoreProgressNotes {
          Button(model.isLoadingMore ? "Loading more progress" : "Load more progress") {
            Task { await model.loadMoreProgressNotes() }
          }
          .buttonStyle(.bordered)
          .frame(maxWidth: .infinity, minHeight: 44)
          .disabled(model.isLoadingMore)
          .accessibilityIdentifier("detail.progress.loadMore")
        }
        if !isAddingNote, !model.unresolvedStatusWrite {
          recovery
        }
      }
      .onChange(of: logEditor == nil) { _, isDismissed in
        if isAddingNote && isDismissed {
          isAddingNote = false
          revealSavedNote(proxy)
        }
      }
      .task(id: highlightedNoteID) {
        guard highlightedNoteID != nil else { return }
        do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
        withAnimation(Theme.motion) { highlightedNoteID = nil }
      }
      .photoViewer(progressPhotos)
    }
  }

  private var header: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    return layout {
      Text("Progress")
        .font(.title3.weight(.semibold))
        .foregroundStyle(theme.foreground)
        .accessibilityAddTraits(.isHeader)
      if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
      Button {
        isAddingNote = true
        logEditor = model
      } label: {
        Label("Log progress", systemImage: "plus.circle")
          .font(.subheadline)
          .frame(minHeight: 44)
      }
      .buttonStyle(.plain)
      .foregroundStyle(theme.pageAction)
      .disabled(model.isMutating || model.unresolvedWriteState != nil)
      .accessibilityIdentifier("detail.progress.addNote")
    }
  }

  @ViewBuilder
  private var recovery: some View {
    switch model.unresolvedWriteState {
    case .needsRefresh:
      if let message = model.mutationErrorMessage { AccessibleErrorLabel(message: message) }
      Button("Refresh note status") {
        Task {
          if await model.refreshUnresolvedWriteStatus() { await onCollectionChanged() }
        }
      }
      .buttonStyle(.bordered)
      .disabled(model.isMutating)
    case .refreshed:
      if let message = model.mutationErrorMessage {
        Label(message, systemImage: "checkmark.circle")
          .foregroundStyle(theme.foreground)
      }
      Button("Done reviewing progress notes") { model.clearUnresolvedWriteRecovery() }
        .buttonStyle(.bordered)
    case nil:
      EmptyView()
    }
  }

  private var pendingNoteID: String? {
    model.lastAddedProgressNoteID == revealedNoteID ? nil : model.lastAddedProgressNoteID
  }

  private var progressPhotos: [DetailPhoto] {
    model.progressNotes.compactMap { note in
      guard let thumbnail = protectedFiles?.photoURL(for: note, thumb: ArtworkThumb.gallery),
        let fullSize = protectedFiles?.photoURL(for: note)
      else { return nil }
      return DetailPhoto(
        id: note.id, url: thumbnail, fullSizeURL: fullSize,
        accessibilityLabel: "Progress photo from \(DetailDateOnly.formatted(note.date) ?? note.date)",
        date: DetailDateOnly.formatted(note.date), caption: note.content.nonEmpty)
    }
  }

  private func revealSavedNote(_ proxy: ScrollViewProxy) {
    guard let id = pendingNoteID else { return }
    withAnimation(reduceMotion ? nil : Theme.motion) {
      if let onReveal {
        onReveal("note-\(id)")
      } else {
        proxy.scrollTo("note-\(id)", anchor: .center)
      }
      revealedNoteID = id
      highlightedNoteID = id
    }
  }
}

struct ProgressNoteEditor: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            if isPreparingPhoto || previewImage != nil {
              photoPreview
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

          if model.isMutating {
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
      .navigationTitle("Log progress")
      .navigationBarTitleDisplayMode(.inline)
      .interactiveDismissDisabled(model.isMutating)
      .accessibilityIdentifier("detail.progress.noteEditor")
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
            .accessibilityIdentifier("detail.progress.noteRefresh")
          case .refreshed:
            Button("Back to notes") {
              model.clearUnresolvedWriteRecovery()
              dismiss()
            }
            .accessibilityIdentifier("detail.progress.noteReview")
          case nil:
            Button(model.mutationErrorMessage == nil ? "Add" : "Try again") {
              Task { await submit() }
            }
            .disabled(!canSubmit || isPreparingPhoto || model.isMutating)
            .accessibilityIdentifier(
              model.mutationErrorMessage == nil
                ? "detail.progress.noteSubmit" : "detail.progress.noteRetry"
            )
          }
        }
      }
      .task(id: selectedItem) {
        await prepareSelectedPhoto()
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    .task { _ = await model.load() }
    .sensoryFeedback(.success, trigger: model.lastAddedProgressNoteID) { _, saved in saved != nil }
  }

  /// A fixed 4:5 frame, so preparing and the finished preview never move the form.
  private var photoPreview: some View {
    ZStack {
      RoundedRectangle(cornerRadius: Theme.Radius.medium)
        .fill(theme.muted.opacity(0.45))
      if let previewImage {
        Image(uiImage: previewImage)
          .resizable()
          .scaledToFit()
          .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
          .transition(.opacity)
          .accessibilityLabel("Selected progress photo")
          .accessibilityIdentifier("detail.progress.notePhoto")
      } else {
        ProgressView("Preparing photo…")
          .transition(.opacity)
      }
    }
    .aspectRatio(4 / 5, contentMode: .fit)
    .frame(maxHeight: dynamicTypeSize.isAccessibilitySize ? 440 : 320)
    .frame(maxWidth: .infinity)
    .animation(Theme.motion, value: previewImage)
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
    if await model.addProgressNote(content: content, date: date, photo: processedPhoto) {
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
