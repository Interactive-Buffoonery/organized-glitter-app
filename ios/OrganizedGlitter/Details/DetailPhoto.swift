import CoreTransferable
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct DetailPhoto: Identifiable, Hashable, Sendable {
  let id: String
  let url: URL
  let accessibilityLabel: String
}

struct DetailPhotoGallery: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let photos: [DetailPhoto]

  var body: some View {
    ScrollView(.horizontal) {
      LazyHStack(spacing: 12) {
        ForEach(photos) { photo in
          DetailPhotoTile(photo: photo, contentMode: .fit, maxPixelDimension: thumbnailSize * 3)
            .frame(width: thumbnailSize, height: thumbnailSize)
        }
      }
    }
    .scrollIndicators(.hidden)
    .accessibilityIdentifier("detail.photos")
  }

  private var thumbnailSize: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? 160 : 104
  }
}

/// Square progress photos in a grid, like the web's contact sheet.
struct DetailPhotoContactSheet: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  let photos: [DetailPhoto]
  var pendingID: String?
  var highlightedID: String?

  var body: some View {
    LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columnCount),
      spacing: 6
    ) {
      ForEach(photos) { photo in
        DetailPhotoTile(photo: photo, contentMode: .fill, maxPixelDimension: 480)
          .aspectRatio(1, contentMode: .fit)
          .savedEntryReveal(isPending: photo.id == pendingID, isHighlighted: photo.id == highlightedID)
          .id("photo-\(photo.id)")
      }
    }
    .accessibilityIdentifier("detail.photos")
  }

  private var columnCount: Int {
    if dynamicTypeSize.isAccessibilitySize { return 2 }
    return horizontalSizeClass == .regular ? 4 : 3
  }
}

extension View {
  /// Keeps a just-saved entry invisible until its sheet closes, then eases it in with a brief ring.
  func savedEntryReveal(isPending: Bool, isHighlighted: Bool) -> some View {
    modifier(SavedEntryReveal(isPending: isPending, isHighlighted: isHighlighted))
  }
}

private struct SavedEntryReveal: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.theme) private var theme

  let isPending: Bool
  let isHighlighted: Bool

  func body(content: Content) -> some View {
    content
      .overlay {
        RoundedRectangle(cornerRadius: Theme.Radius.medium)
          .strokeBorder(theme.primary, lineWidth: 3)
          .opacity(isHighlighted ? 1 : 0)
      }
      .scaleEffect(isPending && !reduceMotion ? 0.92 : 1)
      .opacity(isPending ? 0 : 1)
      .accessibilityHidden(isPending)
  }
}

struct DetailPhotoTile: View {
  @Environment(\.theme) private var theme

  let photo: DetailPhoto
  let contentMode: ContentMode
  let maxPixelDimension: CGFloat

  var body: some View {
    Color.clear
      .overlay {
        RemoteArtwork(url: photo.url, maxPixelDimension: maxPixelDimension) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .aspectRatio(contentMode: contentMode)
              .accessibilityLabel(photo.accessibilityLabel)
          case .failure:
            placeholder(systemImage: "photo.badge.exclamationmark")
              .accessibilityLabel("Photo unavailable")
          case .empty:
            placeholder(systemImage: "photo")
              .overlay { ProgressView() }
              .accessibilityHidden(true)
          @unknown default:
            placeholder(systemImage: "photo")
              .accessibilityHidden(true)
          }
        }
      }
      .background(theme.muted.opacity(0.45))
      .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
  }

  private func placeholder(systemImage: String) -> some View {
    Rectangle()
      .fill(theme.muted)
      .overlay {
        Image(systemName: systemImage)
          .font(.title2)
          .foregroundStyle(theme.mutedForeground)
      }
  }
}

struct ProcessedDetailPhoto: Equatable, Sendable {
  let data: Data
  let fileName: String
  let contentType: String
}

enum DetailPhotoProcessingError: Error, Equatable {
  case inputTooLarge
  case unsupportedImage
  case outputTooLarge

  var message: String {
    switch self {
    case .inputTooLarge:
      "Choose an image smaller than 50 MB."
    case .unsupportedImage:
      "That image could not be read. Choose another photo."
    case .outputTooLarge:
      "That image could not be reduced below 5 MB."
    }
  }
}

enum DetailPhotoProcessor {
  static let maximumInputBytes = 50 * 1_024 * 1_024
  static let maximumOutputBytes = 5 * 1_024 * 1_024
  static let maximumPixelDimension = 2_048

  static func process(item: PhotosPickerItem) async throws -> ProcessedDetailPhoto {
    guard let transfer = try await item.loadTransferable(type: SizedImageTransfer.self) else {
      throw DetailPhotoProcessingError.unsupportedImage
    }
    return try await process(
      data: transfer.data,
      contentTypeIdentifier: item.supportedContentTypes.first?.identifier
    )
  }

  static func process(
    data: Data,
    contentTypeIdentifier: String?,
    originalFileName: String? = nil
  ) async throws -> ProcessedDetailPhoto {
    guard data.count <= maximumInputBytes else {
      throw DetailPhotoProcessingError.inputTooLarge
    }

    let processingTask = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      return try processSynchronously(
        data: data,
        contentTypeIdentifier: contentTypeIdentifier,
        originalFileName: originalFileName
      )
    }
    return try await withTaskCancellationHandler {
      try await processingTask.value
    } onCancel: {
      processingTask.cancel()
    }
  }

  private static func processSynchronously(
    data: Data,
    contentTypeIdentifier: String?,
    originalFileName: String?
  ) throws -> ProcessedDetailPhoto {
    guard let source = CGImageSourceCreateWithData(
      data as CFData,
      [kCGImageSourceShouldCache: false] as CFDictionary
    ),
      CGImageSourceGetCount(source) > 0
    else {
      throw DetailPhotoProcessingError.unsupportedImage
    }

    let sourceType =
      contentTypeIdentifier.flatMap(UTType.init)
      ?? CGImageSourceGetType(source).flatMap { UTType($0 as String) }
    guard sourceType?.conforms(to: .image) == true else {
      throw DetailPhotoProcessingError.unsupportedImage
    }

    let preservePNG = sourceType?.conforms(to: .png) == true
    let dimensions = [2_048, 1_792, 1_536, 1_280, 1_024, 768, 512]

    for dimension in dimensions {
      try Task.checkCancellation()
      guard let image = thumbnail(from: source, maximumDimension: dimension) else {
        throw DetailPhotoProcessingError.unsupportedImage
      }

      if preservePNG,
        let encoded = encode(image: image, type: .png, quality: nil),
        encoded.count <= maximumOutputBytes
      {
        return ProcessedDetailPhoto(
          data: encoded,
          fileName: sanitizedBaseName(originalFileName) + ".png",
          contentType: UTType.png.preferredMIMEType ?? "image/png"
        )
      }

      for quality in stride(from: 0.9, through: 0.45, by: -0.1) {
        try Task.checkCancellation()
        if let encoded = encode(image: image, type: .jpeg, quality: quality),
          encoded.count <= maximumOutputBytes
        {
          return ProcessedDetailPhoto(
            data: encoded,
            fileName: sanitizedBaseName(originalFileName) + ".jpg",
            contentType: UTType.jpeg.preferredMIMEType ?? "image/jpeg"
          )
        }
      }
    }

    throw DetailPhotoProcessingError.outputTooLarge
  }

  private static func thumbnail(
    from source: CGImageSource,
    maximumDimension: Int
  ) -> CGImage? {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: min(maximumDimension, maximumPixelDimension),
      kCGImageSourceShouldCacheImmediately: true,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  private static func encode(
    image: CGImage,
    type: UTType,
    quality: Double?
  ) -> Data? {
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data,
        type.identifier as CFString,
        1,
        nil
      )
    else {
      return nil
    }

    let properties = quality.map {
      [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary
    }
    CGImageDestinationAddImage(destination, image, properties)
    guard CGImageDestinationFinalize(destination) else {
      return nil
    }
    return data as Data
  }

  private static func sanitizedBaseName(_ originalFileName: String?) -> String {
    let base = originalFileName?
      .split(separator: ".")
      .dropLast()
      .joined(separator: ".")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let sanitized = base?
      .unicodeScalars
      .map { allowed.contains($0) ? Character(String($0)) : "-" }
    let value = sanitized.map { String($0) }?.nonEmpty ?? "artwork"
    return String(value.prefix(60))
  }
}

struct SizedImageTransfer: Transferable {
  let data: Data

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType: .image) { received in
      let size =
        try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size <= DetailPhotoProcessor.maximumInputBytes else {
        throw DetailPhotoProcessingError.inputTooLarge
      }
      return SizedImageTransfer(data: try Data(contentsOf: received.file))
    }
    DataRepresentation(importedContentType: .image) { data in
      guard data.count <= DetailPhotoProcessor.maximumInputBytes else {
        throw DetailPhotoProcessingError.inputTooLarge
      }
      return SizedImageTransfer(data: data)
    }
  }
}
