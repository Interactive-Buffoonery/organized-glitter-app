import PhotosUI
import SwiftUI
import UIKit

struct ColoringPageDetailView: View {
  @Environment(\.connectionAvailable) private var connectionAvailable
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.theme) private var theme

  let page: ColoringPageRecord
  let model: LibraryItemDetailModel
  @Binding var logEditor: LibraryItemDetailModel?
  let onCollectionChanged: @MainActor @Sendable () async -> Void

  @State private var deletingPhoto: String?
  @State private var selectedItem: PhotosPickerItem?
  @State private var pendingPhoto: ProcessedDetailPhoto?
  @State private var pendingPreview: UIImage?
  @State private var isPreparingPhoto = false
  @State private var photoErrorMessage: String?
  @State private var revealDraft = ""
  @State private var showingRevealAlert = false
  @State private var editingReveal = false
  @State private var confirmingHide = false
  @State private var revealErrorMessage: String?

  private var mystery: MysteryPagePresentation {
    MysteryPagePresentation(page: page, isMystery: model.library.isMysteryBook(page.book))
  }

  private var revealControlsDisabled: Bool {
    model.isMutating || model.unresolvedWriteState != nil || isPreparingPhoto || pendingPhoto != nil || hasMediumRecovery
  }

  @State private var showingMediumEditor = false

  private var hasMediumRecovery: Bool {
    model.library.mediumAttempts.contains { $0.pageID == page.id }
  }

  var body: some View {
    let startedDate = page.startedAt.flatMap { DetailDateOnly.date($0) }
    let completedDate = page.completedAt.flatMap { DetailDateOnly.date($0) }
    let today = Date.now
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 18) {
          CoverArtwork(
            item: .page(page),
            url: protectedFiles?.artworkURL(for: .page(page), thumb: ArtworkThumb.gallery),
            maxPixelDimension: 1_200,
            loadedAccessibilityLabel: "Page artwork"
          )
          .frame(maxWidth: .infinity, maxHeight: heroHeight)
          .photoViewer(opening: coverPhoto, library: model.library, surface: .coloringPageCover)
          .accessibilityIdentifier("detail.hero")

          VStack(alignment: .leading, spacing: 6) {
            if mystery.isMystery {
              mysteryTitle
                .accessibilityAddTraits(.isHeader)
              if mystery.isRevealed, let date = page.revealedAt.flatMap({ DetailDateOnly.formatted($0) }) {
                Text("Revealed \(date)")
                  .font(.karla(.subheadline))
                  .foregroundStyle(theme.pageSecondaryForeground)
                  .fixedSize(horizontal: false, vertical: true)
                  .accessibilityIdentifier("detail.page.revealedDate")
              }
            } else {
              DetailInlineTitle(
                value: page.revealedSubject ?? "",
                placeholder: "Page \(page.pageNumber)",
                field: "revealed_subject",
                label: "Revealed subject",
                allowsEmpty: true,
                model: model,
                onCollectionChanged: onCollectionChanged)
                .disabled(hasMediumRecovery)
            }
            Text(subtitle)
              .accessibilityIdentifier("detail.page.subtitle")
              .font(.karla(.body))
              .foregroundStyle(theme.pageSecondaryForeground)
          }

          DetailStatusMenu<PageStatus>(
            current: page.status, model: model, onCollectionChanged: onCollectionChanged)
            .disabled(hasMediumRecovery)
          DetailStatusRecovery(model: model, onCollectionChanged: onCollectionChanged)

          if mystery.isMystery && !mystery.isRevealed {
            VStack(alignment: .leading, spacing: 12) {
              Label("Still a mystery", systemImage: "questionmark.square.dashed")
                .font(.karla(.headline))
              Text("What did it turn out to be?")
                .fixedSize(horizontal: false, vertical: true)
              Button("Reveal") {
                editingReveal = false
                showingRevealAlert = true
              }
              .buttonStyle(.bordered)
              .disabled(revealControlsDisabled)
              .accessibilityIdentifier("detail.page.reveal")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
          }
          if let revealErrorMessage { AccessibleErrorLabel(message: revealErrorMessage) }

          VStack(alignment: .leading, spacing: 12) {
            Label("Mediums", systemImage: "pencil.tip")
              .font(.karla(.headline))
            Text(MediumNames.summary(ids: page.selectedMediumIDs, options: page.expand?.mediums ?? []))
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("detail.page.mediumNames")
            Button(hasMediumRecovery ? "Review medium save" : page.selectedMediumIDs.isEmpty ? "Add mediums" : "Edit mediums") {
              showingMediumEditor = true
            }
            .buttonStyle(.bordered)
            .disabled((!connectionAvailable && !hasMediumRecovery) || model.isMutating || model.unresolvedWriteState != nil
              || pendingPhoto != nil || isPreparingPhoto)
            .accessibilityIdentifier("detail.page.mediums")
            if !hasMediumRecovery { NeedsConnectionHint() }
          }

          VStack(alignment: .leading, spacing: 12) {
            photoHeader

            if photos.isEmpty {
              ContentUnavailableView(
                "No page photos",
                systemImage: "photo.on.rectangle",
                description: Text("Add the first photo of this page.")
              )
              .frame(maxWidth: .infinity)
            } else {
              DetailPhotoGallery(photos: photos, actions: galleryPhotoActions)
            }

            if isPreparingPhoto {
              ProgressView("Preparing photo…")
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if model.isMutating,
              model.isChangingPagePhoto || model.unresolvedPhotoAction || model.unresolvedPagePhotoUpload {
              ProgressView(
                pendingPhoto != nil || model.unresolvedPagePhotoUpload
                  ? (model.unresolvedWriteState == nil ? "Uploading photo…" : "Checking upload status…")
                  : "Saving photo change…"
              )
              .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let message = photoErrorMessage {
              AccessibleErrorLabel(message: message)
            }

            if pendingPhoto == nil, let message = model.photoMutationErrorMessage {
              AccessibleErrorLabel(message: message)
            }
            if model.unresolvedPhotoAction {
              if model.unresolvedWriteState == .needsRefresh {
                Button("Refresh photos", systemImage: "arrow.clockwise") {
                  Task {
                    if await model.refreshUnresolvedWriteStatus() { await onCollectionChanged() }
                  }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.isMutating || !connectionAvailable)
                .accessibilityIdentifier("detail.page.photoActionRefresh")
              } else if model.unresolvedWriteState == .refreshed {
                Button("Back to photos") { Task { await model.clearUnresolvedWriteRecovery() } }
                  .buttonStyle(.bordered)
                  .controlSize(.large)
                  .disabled(model.isMutating)
                  .accessibilityIdentifier("detail.page.photoActionReview")
              }
            }

            if let pendingPhoto {
              if let preview = pendingPreview {
                Image(uiImage: preview)
                  .resizable()
                  .scaledToFit()
                  .frame(maxWidth: .infinity, maxHeight: 240)
                  .clipShape(.rect(cornerRadius: Theme.Radius.medium))
                  .accessibilityLabel("Selected page photo")
                  .accessibilityIdentifier("detail.page.photoPreview")
              }
              switch model.unresolvedWriteState {
              case .needsRefresh:
                if let message = model.mutationErrorMessage {
                  AccessibleErrorLabel(message: message)
                }
                Button {
                  Task { await refreshUploadStatus() }
                } label: {
                  Label("Refresh status", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isMutating)
                .accessibilityIdentifier("detail.page.photoRefresh")

              case .refreshed:
                if let message = model.mutationErrorMessage {
                  Label(message, systemImage: "checkmark.circle")
                    .foregroundStyle(theme.foreground)
                }
                Button("Back to photos") {
                  clearPendingPhoto(clearRecovery: true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("detail.page.photoReview")

              case nil:
                if let message = model.mutationErrorMessage {
                  AccessibleErrorLabel(message: message)
                }
                Button {
                  Task { await upload(pendingPhoto) }
                } label: {
                  Label(
                    model.mutationErrorMessage == nil ? "Add photo" : "Try upload again",
                    systemImage: model.mutationErrorMessage == nil ? "plus" : "arrow.clockwise"
                  )
                  .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isPreparingPhoto || model.isMutating || !connectionAvailable)
                .accessibilityIdentifier(
                  model.mutationErrorMessage == nil
                    ? "detail.page.photoSubmit" : "detail.page.photoRetry"
                )

                Button("Discard pending upload", role: .cancel) {
                  clearPendingPhoto()
                }
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(model.isMutating)
              }
            }
          }

          ProgressNotesSection(
            model: model, onCollectionChanged: onCollectionChanged,
            logEditor: $logEditor,
            onReveal: { proxy.scrollTo($0, anchor: .center) })

          VStack(alignment: .leading, spacing: 12) {
            Text("Page details")
              .font(.karla(.title3).weight(.semibold))
              .foregroundStyle(theme.foreground)
              .accessibilityAddTraits(.isHeader)
            DetailMetadataCard {
              DetailDateRow(
                label: "Started",
                value: page.startedAt,
                isDisabled: model.isMutating || model.unresolvedWriteState != nil || hasMediumRecovery,
                maximumDate: min(completedDate ?? today, today)
              ) { date in
                saveDetailChange(
                  { await model.setDate("started_at", to: date) },
                  onCollectionChanged: onCollectionChanged)
              }
              DetailDateRow(
                label: "Completed",
                value: page.completedAt,
                isDisabled: model.isMutating || model.unresolvedWriteState != nil || hasMediumRecovery,
                minimumDate: startedDate,
                maximumDate: today
              ) { date in
                saveDetailChange(
                  { await model.setDate("completed_at", to: date) },
                  onCollectionChanged: onCollectionChanged)
              }
            }
          }

          DetailLoadError(model: model)
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
      .photoViewer(photos, library: model.library, surface: .coloringPageGallery,
        actions: viewerPhotoActions)
      .photoDeleteConfirmation($deletingPhoto, isEnabled: photoActionsEnabled) { id in
        Task { await changePhoto(id, setMain: false) }
      }
      .task(id: selectedItem) {
        await prepareSelection()
      }
    }
    .alert(editingReveal ? "Edit answer" : "Reveal page", isPresented: $showingRevealAlert) {
      TextField("Subject", text: $revealDraft)
        .accessibilityIdentifier("mystery.subject")
      Button("Cancel", role: .cancel) {}
      Button(editingReveal ? "Save" : "Reveal") { saveReveal() }
        .disabled(revealDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || revealControlsDisabled)
    }
    .confirmationDialog("Hide the answer?", isPresented: $confirmingHide, titleVisibility: .visible) {
      Button("Hide again", role: .destructive) { hideReveal() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The page goes back to being a mystery.")
    }
    .sheet(isPresented: $showingMediumEditor) {
      PageMediumEditor(page: page, model: model, onCollectionChanged: onCollectionChanged)
    }
  }

  private var subtitle: String {
    let bookTitle = page.expand?.book?.title ?? "Coloring book"
    return mystery.isRevealed ? "\(bookTitle) · Page \(page.pageNumber)" : bookTitle
  }

  @ViewBuilder
  private var mysteryTitle: some View {
    if mystery.isRevealed {
      Menu {
        Button("Edit answer") {
          editingReveal = true
          revealDraft = page.revealedSubject ?? ""
          showingRevealAlert = true
        }
        .accessibilityIdentifier("detail.page.editAnswer")
        Button("Hide again", role: .destructive) { confirmingHide = true }
          .accessibilityIdentifier("detail.page.hide")
      } label: {
        HStack(alignment: .firstTextBaseline) {
          Text(mystery.title)
            .fixedSize(horizontal: false, vertical: true)
          Image(systemName: "chevron.down").font(.karla(.caption))
            .accessibilityHidden(true)
        }
        .font(.karla(.title3).weight(.semibold))
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(.rect)
      }
      .disabled(revealControlsDisabled)
      .accessibilityIdentifier("detail.page.answerMenu")
    } else {
      Text(mystery.title)
        .font(.karla(.title3).weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func saveReveal() {
    guard !revealControlsDisabled else { return }
    revealErrorMessage = nil
    let isEditing = editingReveal
    let today = DetailDateOnly.string(from: Date.now)
    do {
      let patch = try isEditing
        ? MysteryRevealWrite.editAnswer(revealDraft)
        : MysteryRevealWrite.reveal(subject: revealDraft, day: today, today: today)
      Task {
        if await model.updateFields(patch) {
          await onCollectionChanged()
          AccessibilityNotification.Announcement(isEditing ? "Answer saved" : "Revealed").post()
          revealDraft = ""
        }
      }
    } catch {
      revealErrorMessage = "Enter a subject and a valid reveal date."
    }
  }

  private func hideReveal() {
    guard !revealControlsDisabled else { return }
    Task {
      if await model.updateFields(MysteryRevealWrite.hide) {
        await onCollectionChanged()
        revealDraft = ""
        AccessibilityNotification.Announcement("Answer hidden").post()
      }
    }
  }

  private var photoActionsEnabled: Bool {
    connectionAvailable && !model.isMutating && model.unresolvedWriteState == nil
      && pendingPhoto == nil && selectedItem == nil && !isPreparingPhoto
  }

  private var galleryPhotoActions: DetailPhotoActions {
    DetailPhotoActions(mainID: page.photos.first, isEnabled: photoActionsEnabled,
      setMain: { filename in Task { await changePhoto(filename, setMain: true) } },
      delete: { deletingPhoto = $0 })
  }

  private var viewerPhotoActions: DetailPhotoActions {
    DetailPhotoActions(mainID: page.photos.first, isEnabled: photoActionsEnabled,
      setMain: { filename in Task { await changePhoto(filename, setMain: true) } },
      delete: { filename in Task { await changePhoto(filename, setMain: false) } })
  }

  private func changePhoto(_ filename: String, setMain: Bool) async {
    guard photoActionsEnabled else { return }
    deletingPhoto = nil
    let saved = setMain ? await model.setMainPagePhoto(filename) : await model.deletePagePhoto(filename)
    if saved {
      await onCollectionChanged()
      AccessibilityNotification.Announcement(setMain ? "Main photo updated" : "Photo deleted").post()
    } else if model.unresolvedWriteState != nil {
      AccessibilityNotification.Announcement("Review photo action status before changing photos again").post()
    }
  }

  private var photos: [DetailPhoto] {
    page.photos.enumerated().compactMap { index, filename in
      guard !filename.isEmpty,
        let url = protectedFiles?.url(
          collection: "coloring_pages", recordID: page.id, filename: filename,
          thumb: ArtworkThumb.compact),
        let fullSizeURL = protectedFiles?.url(
          collection: "coloring_pages", recordID: page.id, filename: filename)
      else { return nil }
      return DetailPhoto(
        id: filename,
        url: url,
        fullSizeURL: fullSizeURL,
        accessibilityLabel: "Page photo \(index + 1)"
          + pagePhotoSubjectSuffix
      )
    }
  }

  private var coverPhoto: DetailPhoto? {
    guard let url = protectedFiles?.artworkURL(for: .page(page)) else { return nil }
    return DetailPhoto(
      id: "page-cover", url: url, fullSizeURL: url,
      accessibilityLabel: "Page artwork"
    )
  }

  private var photoHeader: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
      : AnyLayout(HStackLayout())
    return layout {
      Text("Photos")
        .font(.karla(.title3).weight(.semibold))
        .foregroundStyle(theme.foreground)
        .accessibilityAddTraits(.isHeader)
      if !dynamicTypeSize.isAccessibilitySize {
        Spacer()
      }
      if pendingPhoto == nil {
        VStack(alignment: .trailing, spacing: 2) {
          PhotosPicker(selection: $selectedItem, matching: .images) {
            Label("Add photo", systemImage: "plus")
              .frame(minHeight: 44)
              .contentShape(.rect)
          }
          .buttonStyle(.bordered)
          .disabled(isPreparingPhoto || model.isMutating || model.unresolvedWriteState != nil || !connectionAvailable || hasMediumRecovery)
          .accessibilityIdentifier("detail.page.addPhoto")
          NeedsConnectionHint()
        }
      }
    }
  }

  private var heroHeight: CGFloat {
    horizontalSizeClass == .regular ? 360 : 250
  }

  private var pagePhotoSubjectSuffix: String {
    guard let subject = page.revealedSubject?.nonEmpty else { return "" }
    return ": \(subject)"
  }

  private func prepareSelection() async {
    guard let selectedItem else { return }
    isPreparingPhoto = true
    photoErrorMessage = nil
    model.clearPhotoError()
    pendingPhoto = nil
    pendingPreview = nil
    AccessibilityNotification.Announcement("Preparing photo").post()
    defer { isPreparingPhoto = false }
    do {
      let photo = try await DetailPhotoProcessor.process(item: selectedItem)
      try Task.checkCancellation()
      pendingPhoto = photo
      pendingPreview = await Task.detached(priority: .userInitiated) {
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

  private func upload(_ photo: ProcessedDetailPhoto) async {
    photoErrorMessage = nil
    AccessibilityNotification.Announcement("Uploading photo").post()
    if await model.appendPagePhoto(photo) {
      clearPendingPhoto()
      await onCollectionChanged()
      AccessibilityNotification.Announcement("Photo added").post()
    } else if model.unresolvedWriteState == .refreshed {
      AccessibilityNotification.Announcement(
        "Photos refreshed. Review them before starting another upload."
      ).post()
    }
  }

  private func refreshUploadStatus() async {
    AccessibilityNotification.Announcement("Refreshing upload status").post()
    if await model.refreshUnresolvedWriteStatus() {
      await onCollectionChanged()
      AccessibilityNotification.Announcement("Photos refreshed").post()
    }
  }

  private func clearPendingPhoto(clearRecovery: Bool = false) {
    pendingPhoto = nil
    pendingPreview = nil
    selectedItem = nil
    photoErrorMessage = nil
    if clearRecovery {
      Task { await model.clearUnresolvedWriteRecovery() }
    } else {
      model.clearPhotoError()
    }
  }
}
