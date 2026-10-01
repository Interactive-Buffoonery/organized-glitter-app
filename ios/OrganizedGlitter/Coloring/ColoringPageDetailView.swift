import PhotosUI
import SwiftUI
import UIKit

struct ColoringPageDetailView: View {
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.theme) private var theme

  let page: ColoringPageRecord
  let model: LibraryItemDetailModel
  @Binding var logEditor: LibraryItemDetailModel?
  let onCollectionChanged: @MainActor @Sendable () async -> Void

  @State private var selectedItem: PhotosPickerItem?
  @State private var pendingPhoto: ProcessedDetailPhoto?
  @State private var pendingPreview: UIImage?
  @State private var isPreparingPhoto = false
  @State private var photoErrorMessage: String?

  var body: some View {
    let startedDate = formattedDate(page.startedAt)
    let completedDate = formattedDate(page.completedAt)

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
          .photoViewer(opening: coverPhoto)
          .accessibilityIdentifier("detail.hero")

          VStack(alignment: .leading, spacing: 6) {
            DetailInlineTitle(
              value: page.revealedSubject ?? "",
              placeholder: "Page \(page.pageNumber)",
              field: "revealed_subject",
              label: "Revealed subject",
              allowsEmpty: true,
              model: model,
              onCollectionChanged: onCollectionChanged)
            Text("\(page.expand?.book?.title ?? "Coloring book") · Page \(page.pageNumber)")
              .font(.karla(.body))
              .foregroundStyle(theme.pageSecondaryForeground)
          }

          DetailStatusMenu<PageStatus>(
            current: page.status, model: model, onCollectionChanged: onCollectionChanged)
          DetailStatusRecovery(model: model, onCollectionChanged: onCollectionChanged)

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
                .disabled(isPreparingPhoto || model.isMutating)
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

          if startedDate != nil || completedDate != nil {
            VStack(alignment: .leading, spacing: 12) {
              Text("Page details")
                .font(.karla(.title3).weight(.semibold))
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
      .refreshable { await model.refresh() }
      .photoViewer(photos)
      .task(id: selectedItem) {
        await prepareSelection()
      }
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

  private func formattedDate(_ value: String?) -> String? {
    guard let value = value?.nonEmpty else { return nil }
    return DetailDateOnly.formatted(value)
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
          .disabled(isPreparingPhoto || model.isMutating)
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
    model.mutationErrorMessage = nil
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
      model.clearUnresolvedWriteRecovery()
    } else {
      model.mutationErrorMessage = nil
    }
  }
}
