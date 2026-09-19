import PhotosUI
import SwiftUI

struct ColoringPageDetailView: View {
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
          emptyMinHeight: 180
        )
        .frame(maxWidth: .infinity, maxHeight: heroHeight)
        .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
        .clipShape(.rect(cornerRadius: Theme.Radius.medium))
        .accessibilityLabel("Page artwork")
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
          Text("Photos")
            .font(.title3.weight(.semibold))
            .foregroundStyle(theme.foreground)
            .accessibilityAddTraits(.isHeader)

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
          }

          if let message = photoErrorMessage ?? model.mutationErrorMessage {
            AccessibleErrorLabel(message: message)
          }

          if let pendingPhoto {
            Button {
              Task { await upload(pendingPhoto) }
            } label: {
              Label("Retry photo upload", systemImage: "arrow.clockwise")
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
          } else {
            PhotosPicker(selection: $selectedItem, matching: .images) {
              Label("Add photo", systemImage: "plus")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isPreparingPhoto || model.isMutating)
            .accessibilityIdentifier("detail.page.addPhoto")
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
      )
    }
  }

  private func formattedDate(_ value: String?) -> String? {
    guard let value = value?.nonEmpty else { return nil }
    guard let date = parsedDate(value) else { return nil }
    return date.formatted(date: .abbreviated, time: .omitted)
  }

  private func parsedDate(_ value: String) -> Date? {
    if let date = PocketBaseDate.date(from: value) {
      return date
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = .current
    for format in ["yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
      formatter.dateFormat = format
      if let date = formatter.date(from: value) {
        return date
      }
    }
    return nil
  }

  private var heroHeight: CGFloat {
    horizontalSizeClass == .regular ? 360 : 280
  }

  private func prepareAndUploadSelection() async {
    guard let selectedItem else { return }
    isPreparingPhoto = true
    photoErrorMessage = nil
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
    } catch {
      photoErrorMessage = "That photo could not be prepared. Try another image."
    }
  }

  private func upload(_ photo: ProcessedDetailPhoto) async {
    photoErrorMessage = nil
    if await model.appendPagePhoto(photo) {
      clearPendingPhoto()
      await onCollectionChanged()
    }
  }

  private func clearPendingPhoto() {
    pendingPhoto = nil
    selectedItem = nil
    photoErrorMessage = nil
    model.mutationErrorMessage = nil
  }
}
