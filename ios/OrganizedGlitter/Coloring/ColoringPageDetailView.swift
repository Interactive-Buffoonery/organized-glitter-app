import PhotosUI
import SwiftUI

struct ColoringPageDetailView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.theme) private var theme

  let page: ColoringPageRecord
  let model: LibraryItemDetailModel
  let onCollectionChanged: @MainActor @Sendable () async -> Void

  @State private var selectedItem: PhotosPickerItem?
  @State private var pendingPhoto: ProcessedDetailPhoto?
  @State private var isPreparingPhoto = false
  @State private var photoErrorMessage: String?

  var body: some View {
    let startedDate = formattedDate(page.startedAt)
    let completedDate = formattedDate(page.completedAt)

    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        RecordArtwork(
          url: LibraryItem.page(page).artworkURL(using: model.client),
          maxHeight: heroHeight,
          emptyMinHeight: 180,
          successAccessibilityLabel: "Page artwork"
        )
        .frame(maxWidth: .infinity, maxHeight: heroHeight)
        .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
        .clipShape(.rect(cornerRadius: Theme.Radius.medium))
        .accessibilityIdentifier("detail.hero")

        VStack(alignment: .leading, spacing: 6) {
          Text(LibraryItem.page(page).title)
            .font(.title2.bold())
            .foregroundStyle(theme.foreground)
            .accessibilityAddTraits(.isHeader)
          Text("\(page.expand?.book?.title ?? "Coloring book") · Page \(page.pageNumber)")
            .font(.body)
            .foregroundStyle(theme.pageSecondaryForeground)
        }

        DetailMetadataCard {
          DetailMetadataRow(label: "Status") {
            StatusBadge(status: page.status, presentation: .quiet)
          }
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
            DetailPhotoGallery(photos: photos)
          }

          if isPreparingPhoto {
            ProgressView("Preparing photo…")
              .frame(maxWidth: .infinity, alignment: .leading)
          } else if model.isMutating {
            ProgressView(
              model.unresolvedWriteState == nil ? "Uploading photo…" : "Checking upload status…"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
          }

          if let message = photoErrorMessage {
            AccessibleErrorLabel(message: message)
          }

          if let pendingPhoto {
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
                Label("Try upload again", systemImage: "arrow.clockwise")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.large)
              .disabled(isPreparingPhoto || model.isMutating)
              .accessibilityIdentifier("detail.page.photoRetry")

              Button("Discard pending upload", role: .cancel) {
                clearPendingPhoto()
              }
              .frame(maxWidth: .infinity)
              .disabled(model.isMutating)
            }
          }
        }

        if startedDate != nil || completedDate != nil {
          VStack(alignment: .leading, spacing: 12) {
            Text("Page details")
              .font(.title3.weight(.semibold))
              .foregroundStyle(theme.foreground)
              .accessibilityAddTraits(.isHeader)
            DetailMetadataCard {
              if let startedAt = startedDate {
                DetailMetadataRow(label: "Started", value: startedAt)
              }
              if let completedAt = completedDate {
                DetailMetadataRow(label: "Completed", value: completedAt)
              }
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
    .task(id: selectedItem) {
      await prepareAndUploadSelection()
    }
  }

  private var photos: [DetailPhoto] {
    page.photos.enumerated().compactMap { index, filename in
      guard !filename.isEmpty else { return nil }
      return DetailPhoto(
        id: filename,
        url: model.client.fileURL(
          collection: "coloring_pages",
          recordID: page.id,
          filename: filename
        ),
        accessibilityLabel: "Page photo \(index + 1)"
          + pagePhotoSubjectSuffix
      )
    }
  }

  private func formattedDate(_ value: String?) -> String? {
    guard let value = value?.nonEmpty else { return nil }
    return DetailDateOnly.formatted(value)
  }

  private var photoHeader: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
      : AnyLayout(HStackLayout())
    return layout {
      Text("Photos")
        .font(.title3.weight(.semibold))
        .foregroundStyle(theme.foreground)
        .accessibilityAddTraits(.isHeader)
      if !dynamicTypeSize.isAccessibilitySize {
        Spacer()
      }
      if pendingPhoto == nil {
        PhotosPicker(selection: $selectedItem, matching: .images) {
          Label("Add photo", systemImage: "plus")
            .frame(minHeight: 32)
        }
        .buttonStyle(.bordered)
        .disabled(isPreparingPhoto || model.isMutating)
        .accessibilityIdentifier("detail.page.addPhoto")
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

  private func prepareAndUploadSelection() async {
    guard let selectedItem else { return }
    isPreparingPhoto = true
    photoErrorMessage = nil
    model.mutationErrorMessage = nil
    pendingPhoto = nil
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
      pendingPhoto = photo
      await upload(photo)
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
    selectedItem = nil
    photoErrorMessage = nil
    if clearRecovery {
      model.clearUnresolvedWriteRecovery()
    } else {
      model.mutationErrorMessage = nil
    }
  }
}
