import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct CoverImageSection: View {
  @Environment(\.theme) private var theme
  @Environment(\.pocketBaseClient) private var client
  let currentCoverURL: URL?
  let placeholderSystemImage: String
  let accessibilityNoun: String
  @Binding var change: CoverChange

  @State private var selectedItem: PhotosPickerItem?
  @State private var cropPhoto: CropPhoto?
  @State private var isProcessing = false
  @State private var errorMessage: String?

  private struct CropPhoto: Identifiable {
    let id = UUID()
    let photo: ProcessedDetailPhoto
  }

  private var hasCover: Bool {
    switch change {
    case .replace: true
    case .remove: false
    case .unchanged: currentCoverURL != nil
    }
  }

  var body: some View {
    Section {
      HStack {
        Spacer(minLength: 0)
        Color.clear
          .frame(width: 160, height: 200)
          .overlay {
            if case .replace(let photo) = change, let image = UIImage(data: photo.data) {
              Image(uiImage: image).resizable().scaledToFill()
            } else if change == .unchanged, let currentCoverURL {
              RemoteArtwork(url: currentCoverURL, maxPixelDimension: 480) { phase in
                if case .success(let image) = phase {
                  image.resizable().scaledToFill()
                } else { placeholder }
              }
            } else { placeholder }
          }
          .clipShape(.rect(cornerRadius: Theme.Radius.medium))
          .accessibilityLabel(accessibilityNoun)
        Spacer(minLength: 0)
      }
      PhotosPicker(selection: $selectedItem, matching: .images) {
        Label(hasCover ? "Replace Photo" : "Choose Photo", systemImage: "photo")
          .frame(minHeight: 44)
      }
      .accessibilityLabel("\(hasCover ? "Replace" : "Choose") \(accessibilityNoun)")
      .disabled(isProcessing)
      if hasCover {
        Button("Crop", systemImage: "crop") { Task { await crop() } }
          .frame(minHeight: 44)
          .accessibilityLabel("Crop \(accessibilityNoun)")
          .disabled(isProcessing)
      }
      if hasCover {
        Button("Remove Photo", role: .destructive) {
          change = currentCoverURL == nil ? .unchanged : .remove
          selectedItem = nil
        }
        .frame(minHeight: 44)
        .accessibilityLabel("Remove \(accessibilityNoun)")
      }
      if isProcessing { ProgressView("Preparing photo") }
      if let errorMessage { AccessibleErrorLabel(message: errorMessage) }
    } header: {
      Text(accessibilityNoun)
    }
    .listRowBackground(theme.card)
    .task(id: selectedItem) { await prepareSelection() }
    .fullScreenCover(item: $cropPhoto) { selection in
      CoverCropView(photo: selection.photo) { photo in
        change = .replace(photo)
      }
    }
  }

  private var placeholder: some View {
    theme.muted.overlay {
      Image(systemName: placeholderSystemImage)
        .font(.karla(.title2))
        .foregroundStyle(theme.mutedForeground)
    }
  }

  private func prepareSelection() async {
    guard let selectedItem else { return }
    defer { self.selectedItem = nil }
    await prepare { try await DetailPhotoProcessor.process(item: selectedItem) }
  }

  private func crop() async {
    if case .replace(let photo) = change {
      cropPhoto = CropPhoto(photo: photo)
    } else if let currentCoverURL {
      await prepare(failure: "The current photo could not be loaded. Try again.") {
        try await Self.uploadedPhoto(at: currentCoverURL, client: client)
      }
    }
  }

  /// Recropping starts from the uploaded file at full processing size, not
  /// the preview, so the new crop keeps as much detail as the original.
  private static func uploadedPhoto(
    at url: URL, client: PocketBaseClient?
  ) async throws -> ProcessedDetailPhoto {
    let artwork = try await RemoteArtworkLoader.shared.load(
      from: url, maxPixelDimension: CGFloat(DetailPhotoProcessor.maximumPixelDimension),
      client: client, cachesDecodedImage: false)
    guard let data = UIImage(cgImage: artwork.cgImage).jpegData(compressionQuality: 0.95) else {
      throw DetailPhotoProcessingError.unsupportedImage
    }
    return try await DetailPhotoProcessor.process(
      data: data, contentTypeIdentifier: UTType.jpeg.identifier)
  }

  private func prepare(
    failure: String = "That photo could not be prepared. Try another image.",
    _ work: () async throws -> ProcessedDetailPhoto
  ) async {
    isProcessing = true
    errorMessage = nil
    defer { isProcessing = false }
    do {
      let photo = try await work()
      try Task.checkCancellation()
      cropPhoto = CropPhoto(photo: photo)
    } catch is CancellationError {
      return
    } catch APIError.cancelled {
      return
    } catch let error as DetailPhotoProcessingError {
      errorMessage = error.message
    } catch {
      errorMessage = failure
    }
  }
}

struct CoverCropView: View {
  @Environment(\.dismiss) private var dismiss
  let photo: ProcessedDetailPhoto
  let onChoose: (ProcessedDetailPhoto) -> Void
  @State private var zoom: CGFloat = 1
  @State private var offset: CGSize = .zero
  @GestureState private var drag: CGSize = .zero
  @GestureState private var magnification: CGFloat = 1
  @State private var isProcessing = false
  @State private var errorMessage: String?

  static func cropRect(
    imageSize: CGSize, frameSize: CGSize, scale: CGFloat = 1, offset: CGSize = .zero
  ) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0,
      frameSize.width > 0, frameSize.height > 0 else { return .zero }
    let factor = max(frameSize.width / imageSize.width, frameSize.height / imageSize.height)
      * max(1, scale)
    let width = frameSize.width / factor
    let height = frameSize.height / factor
    let x = (imageSize.width - width) / 2 - offset.width / factor
    let y = (imageSize.height - height) / 2 - offset.height / factor
    return CGRect(
      x: min(max(0, x), imageSize.width - width),
      y: min(max(0, y), imageSize.height - height), width: width, height: height)
  }

  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        let width = min(geometry.size.width - 32, max(80, (geometry.size.height - 180) * 0.8), 480)
        let frame = CGSize(width: width, height: width * 1.25)
        VStack(spacing: 16) {
          Spacer(minLength: 0)
          if let image = UIImage(data: photo.data) {
            let rect = Self.cropRect(
              imageSize: image.size, frameSize: frame,
              scale: zoom * magnification,
              offset: CGSize(width: offset.width + drag.width, height: offset.height + drag.height))
            let factor = frame.width / rect.width
            Color.black
              .frame(width: frame.width, height: frame.height)
              .overlay(alignment: .topLeading) {
                Image(uiImage: image).resizable()
                  .frame(width: image.size.width * factor, height: image.size.height * factor)
                  .offset(x: -rect.minX * factor, y: -rect.minY * factor)
              }
              .clipped()
              .overlay { Rectangle().stroke(.white, lineWidth: 2) }
              .contentShape(Rectangle())
              .gesture(DragGesture().updating($drag) { value, state, _ in
                state = value.translation
              }.onEnded { value in
                offset.width += value.translation.width
                offset.height += value.translation.height
                clamp(imageSize: image.size, frame: frame)
              })
              .simultaneousGesture(MagnifyGesture().updating($magnification) { value, state, _ in
                state = value.magnification
              }.onEnded { value in
                zoom = min(8, max(1, zoom * value.magnification))
                clamp(imageSize: image.size, frame: frame)
              })
              .accessibilityLabel("Cover crop preview")
              .accessibilityAdjustableAction { direction in
                zoom = min(8, max(1, zoom + (direction == .increment ? 0.25 : -0.25)))
                clamp(imageSize: image.size, frame: frame)
              }
            HStack(spacing: 20) {
              Button("Zoom out", systemImage: "minus.magnifyingglass") {
                zoom = max(1, zoom - 0.25)
                clamp(imageSize: image.size, frame: frame)
              }
              .frame(minWidth: 44, minHeight: 44)
              Button("Zoom in", systemImage: "plus.magnifyingglass") { zoom = min(8, zoom + 0.25) }
              .frame(minWidth: 44, minHeight: 44)
              Button("Reset") { zoom = 1; offset = .zero }
                .frame(minWidth: 44, minHeight: 44)
            }
            .labelStyle(.iconOnly)
            .frame(minHeight: 44)
            .disabled(isProcessing)
          }
          if isProcessing { ProgressView("Preparing crop") }
          if let errorMessage { Text(errorMessage).font(.karla(.footnote)) }
          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }.disabled(isProcessing)
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Choose") { Task { await choose(frame: frame) } }.disabled(isProcessing)
          }
        }
      }
      .background(.black)
      .foregroundStyle(.white)
      .navigationTitle("Crop Cover")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarColorScheme(.dark, for: .navigationBar)
      .preferredColorScheme(.dark)
      .interactiveDismissDisabled(isProcessing)
    }
  }

  private func clamp(imageSize: CGSize, frame: CGSize) {
    let rect = Self.cropRect(imageSize: imageSize, frameSize: frame, scale: zoom, offset: offset)
    let factor = frame.width / rect.width
    offset = CGSize(
      width: ((imageSize.width - rect.width) / 2 - rect.minX) * factor,
      height: ((imageSize.height - rect.height) / 2 - rect.minY) * factor)
  }

  private func choose(frame: CGSize) async {
    isProcessing = true
    errorMessage = nil
    defer { isProcessing = false }
    do {
      guard let image = UIImage(data: photo.data) else {
        throw DetailPhotoProcessingError.unsupportedImage
      }
      let rect = Self.cropRect(imageSize: image.size, frameSize: frame, scale: zoom, offset: offset)
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = true
      let data = UIGraphicsImageRenderer(size: rect.size, format: format).jpegData(withCompressionQuality: 0.95) { context in
        UIColor.black.setFill()
        context.fill(CGRect(origin: .zero, size: rect.size))
        image.draw(at: CGPoint(x: -rect.minX, y: -rect.minY))
      }
      let cropped = try await DetailPhotoProcessor.process(data: data, contentTypeIdentifier: "public.jpeg")
      try Task.checkCancellation()
      onChoose(cropped)
      dismiss()
    } catch is CancellationError {
      return
    } catch let error as DetailPhotoProcessingError {
      errorMessage = error.message
    } catch {
      errorMessage = "That crop could not be prepared. Try again."
    }
  }
}
