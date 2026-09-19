import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import OrganizedGlitter

@MainActor
struct DetailPhotoProcessorTests {
  @Test
  func rejectsInputsAboveThePrivateUploadLimit() async {
    let data = Data(count: DetailPhotoProcessor.maximumInputBytes + 1)

    await #expect(throws: DetailPhotoProcessingError.inputTooLarge) {
      try await DetailPhotoProcessor.process(
        data: data,
        contentTypeIdentifier: UTType.jpeg.identifier
      )
    }
  }

  @Test
  func scalesLargeArtworkWithinPixelAndUploadLimits() async throws {
    let sourceSize = CGSize(width: 3_000, height: 1_500)
    let renderer = UIGraphicsImageRenderer(size: sourceSize)
    let source = renderer.image { context in
      UIColor.systemPink.setFill()
      context.fill(CGRect(origin: .zero, size: sourceSize))
      UIColor.systemPurple.setFill()
      context.fill(CGRect(x: 1_500, y: 0, width: 1_500, height: 1_500))
    }
    let input = try #require(source.jpegData(compressionQuality: 1))

    let result = try await DetailPhotoProcessor.process(
      data: input,
      contentTypeIdentifier: UTType.jpeg.identifier,
      originalFileName: "wide artwork.jpeg"
    )

    #expect(result.data.count <= DetailPhotoProcessor.maximumOutputBytes)
    #expect(result.contentType == "image/jpeg")
    #expect(result.fileName == "wide-artwork.jpg")
    let dimensions = try imageDimensions(result.data)
    #expect(max(dimensions.width, dimensions.height) <= 2_048)
    #expect(abs((dimensions.width / dimensions.height) - 2) < 0.02)
  }

  @Test
  func keepsSmallPNGArtworkAsPNG() async throws {
    let size = CGSize(width: 80, height: 120)
    let format = UIGraphicsImageRendererFormat()
    format.opaque = false
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let input = renderer.image { context in
      UIColor.clear.setFill()
      context.fill(CGRect(origin: .zero, size: size))
      UIColor.systemMint.setFill()
      context.cgContext.fillEllipse(in: CGRect(x: 10, y: 30, width: 60, height: 60))
    }.pngData()
    let data = try #require(input)

    let result = try await DetailPhotoProcessor.process(
      data: data,
      contentTypeIdentifier: UTType.png.identifier,
      originalFileName: "page.png"
    )

    #expect(result.contentType == "image/png")
    #expect(result.fileName == "page.png")
    #expect(result.data.count <= DetailPhotoProcessor.maximumOutputBytes)
  }

  @Test
  func appliesSourceOrientationWhilePreservingAspectRatio() async throws {
    let size = CGSize(width: 120, height: 60)
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { context in
      UIColor.systemBlue.setFill()
      context.fill(CGRect(origin: .zero, size: size))
    }
    let cgImage = try #require(image.cgImage)
    let inputData = NSMutableData()
    let destination = try #require(
      CGImageDestinationCreateWithData(
        inputData,
        UTType.jpeg.identifier as CFString,
        1,
        nil
      )
    )
    CGImageDestinationAddImage(
      destination,
      cgImage,
      [kCGImagePropertyOrientation: 6] as CFDictionary
    )
    #expect(CGImageDestinationFinalize(destination))

    let result = try await DetailPhotoProcessor.process(
      data: inputData as Data,
      contentTypeIdentifier: UTType.jpeg.identifier
    )

    let dimensions = try imageDimensions(result.data)
    #expect(dimensions.width == 60)
    #expect(dimensions.height == 120)
  }

  private func imageDimensions(_ data: Data) throws -> (width: Double, height: Double) {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let properties = try #require(
      CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    )
    let width = try #require((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue)
    let height = try #require((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue)
    return (width, height)
  }
}
