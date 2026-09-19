import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct DetailPhoto: Identifiable, Hashable, Sendable {
  let id: String
  let url: URL
  let accessibilityLabel: String
}

struct DetailPhotoGallery: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.theme) private var theme

  let photos: [DetailPhoto]

  var body: some View {
    ScrollView(.horizontal) {
      LazyHStack(spacing: 12) {
        ForEach(photos) { photo in
          RemoteArtwork(url: photo.url, maxPixelDimension: 660) { phase in
            switch phase {
            case .success(let image):
              image
                .resizable()
                .scaledToFit()
                .accessibilityLabel(photo.accessibilityLabel)
            case .failure:
              photoPlaceholder(systemImage: "photo.badge.exclamationmark")
                .accessibilityLabel("Photo unavailable")
            case .empty:
              photoPlaceholder(systemImage: "photo")
                .overlay { ProgressView() }
                .accessibilityHidden(true)
            @unknown default:
              photoPlaceholder(systemImage: "photo")
                .accessibilityHidden(true)
            }
          }
          .frame(width: thumbnailSize, height: thumbnailSize)
          .background(theme.muted.opacity(0.45))
          .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
        }
      }
    }
    .scrollIndicators(.hidden)
    .accessibilityIdentifier("detail.photos")
  }

  private var thumbnailSize: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? 160 : 104
  }

  private func photoPlaceholder(systemImage: String) -> some View {
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
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
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
