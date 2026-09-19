import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import OrganizedGlitter

struct RemoteArtworkTests {
  @Test
  func fixtureRunUsesFixtureTransportAndDecodesArtwork() async throws {
    let session = RemoteArtworkLoader.sessionForDebugRun(isFixtureRun: true)
    defer { session.invalidateAndCancel() }
    let loader = RemoteArtworkLoader(session: session)

    let image = try await loader.load(
      from: URL(
        string:
          "https://overview.example.invalid/api/files/projects/design-project/design-peony.png"
      )!,
      maxPixelDimension: 660
    ).cgImage

    #expect(image.width > 0)
    #expect(image.height > 0)
    #expect(max(image.width, image.height) <= 660)
  }

  @Test
  func downsampleBoundsDecodedPixelsAndAppliesOrientation() throws {
    let data = try jpegData(width: 2_400, height: 1_200, orientation: .right)

    let image = try RemoteArtworkLoader.downsample(
      data: data,
      maxPixelDimension: 660
    ).cgImage

    #expect(max(image.width, image.height) <= 660)
    #expect(image.height > image.width)
    #expect(abs(Double(image.width) / Double(image.height) - 0.5) < 0.02)
  }

  @Test
  func cancellingLoadStopsAnOutstandingRequest() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [NeverCompletingArtworkURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let loader = RemoteArtworkLoader(session: session)
    let task = Task {
      try await loader.load(
        from: URL(string: "https://artwork.example.test/image.jpg")!,
        maxPixelDimension: 660
      )
    }

    try await Task.sleep(for: .milliseconds(20))
    task.cancel()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }
  }

  private func jpegData(
    width: Int,
    height: Int,
    orientation: CGImagePropertyOrientation
  ) throws -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    let context = try #require(
      CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      ))
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let sourceImage = try #require(context.makeImage())

    let data = NSMutableData()
    let destination = try #require(
      CGImageDestinationCreateWithData(
        data,
        UTType.jpeg.identifier as CFString,
        1,
        nil
      ))
    CGImageDestinationAddImage(
      destination,
      sourceImage,
      [kCGImagePropertyOrientation: orientation.rawValue] as CFDictionary
    )
    try #require(CGImageDestinationFinalize(destination))
    return data as Data
  }
}

private final class NeverCompletingArtworkURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {}

  override func stopLoading() {}
}
