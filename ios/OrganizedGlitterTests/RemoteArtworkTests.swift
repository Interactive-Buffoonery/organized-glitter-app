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
          "https://overview.example.invalid/api/files/projects/design-project/design-princesses-rapunzel.jpg"
      )!,
      maxPixelDimension: 660
    ).cgImage

    #expect(image.width > 0)
    #expect(image.height > 0)
    #expect(max(image.width, image.height) <= 660)
  }

  @Test
  func concurrentAndRepeatedLoadsReuseOneFetch() async throws {
    let store = RemoteArtworkDataStore(maximumByteCount: 1_024)
    let probe = ArtworkFetchProbe(data: Data(repeating: 7, count: 128))
    let url = URL(string: "https://artwork.example.test/shared.jpg")!

    async let first = store.data(for: url) { try await probe.fetch() }
    async let second = store.data(for: url) { try await probe.fetch() }
    let (firstData, secondData) = try await (first, second)
    let repeatedData = try await store.data(for: url) { try await probe.fetch() }
    let fetchCount = await probe.fetchCount

    #expect(firstData == secondData)
    #expect(repeatedData == firstData)
    #expect(fetchCount == 1)
  }

  @Test
  func renewedTokenReusesArtworkCacheAndInflightFetch() async throws {
    let store = RemoteArtworkDataStore(maximumByteCount: 1_024)
    let gate = ArtworkFetchGate(data: Data(repeating: 5, count: 128))
    let firstURL = URL(
      string: "https://artwork.example.test/image.jpg?thumb=160x160&token=first")!
    let renewedURL = URL(
      string: "https://artwork.example.test/image.jpg?thumb=160x160&token=renewed")!
    let otherThumb = URL(
      string: "https://artwork.example.test/image.jpg?thumb=320x420&token=renewed")!

    let first = Task { try await store.data(for: firstURL) { try await gate.fetch() } }
    while await store.inFlightWaiterCount(for: firstURL) < 1 {
      await Task.yield()
    }
    let second = Task { try await store.data(for: renewedURL) { try await gate.fetch() } }
    while await store.inFlightWaiterCount(for: renewedURL) < 2 {
      await Task.yield()
    }
    await gate.finish()

    let firstData = try await first.value
    let secondData = try await second.value
    let cachedData = try await store.data(for: renewedURL) { try await gate.fetch() }
    #expect(firstData == secondData)
    #expect(cachedData == firstData)
    #expect(await gate.fetchCount == 1)
    #expect(await store.cachedEntryCount == 1)
    #expect(RemoteArtworkCacheKey.url(for: firstURL) == RemoteArtworkCacheKey.url(for: renewedURL))
    #expect(RemoteArtworkCacheKey.url(for: firstURL) != RemoteArtworkCacheKey.url(for: otherThumb))
  }

  @Test
  func cancellingOneWaiterReturnsPromptlyWithoutCancellingTheSharedFetch() async throws {
    let store = RemoteArtworkDataStore(maximumByteCount: 1_024)
    let gate = ArtworkFetchGate(data: Data(repeating: 9, count: 128))
    let url = URL(string: "https://artwork.example.test/coalesced.jpg")!
    let first = Task {
      try await store.data(for: url) { try await gate.fetch() }
    }
    while await store.inFlightWaiterCount(for: url) < 1 {
      await Task.yield()
    }
    let second = Task {
      try await store.data(for: url) { try await gate.fetch() }
    }
    while await store.inFlightWaiterCount(for: url) < 2 {
      await Task.yield()
    }

    first.cancel()
    let cancelledPromptly = await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        do {
          _ = try await first.value
          return false
        } catch is CancellationError {
          return true
        } catch {
          return false
        }
      }
      group.addTask {
        try? await Task.sleep(for: .milliseconds(250))
        return false
      }
      let result = await group.next() ?? false
      await gate.finish()
      group.cancelAll()
      return result
    }

    let secondData = try await second.value
    let fetchCount = await gate.fetchCount
    let cachedByteCount = await store.cachedByteCount
    #expect(cancelledPromptly)
    #expect(secondData == Data(repeating: 9, count: 128))
    #expect(fetchCount == 1)
    #expect(cachedByteCount == 128)
  }

  @Test
  func encodedCacheStaysWithinItsMemoryLimit() async throws {
    let store = RemoteArtworkDataStore(maximumByteCount: 10)

    for index in 0..<3 {
      let url = URL(string: "https://artwork.example.test/\(index).jpg")!
      _ = try await store.data(for: url) {
        Data(repeating: UInt8(index), count: 6)
      }
    }

    let cachedByteCount = await store.cachedByteCount
    let cachedEntryCount = await store.cachedEntryCount
    #expect(cachedByteCount <= 10)
    #expect(cachedEntryCount == 1)
  }

  @Test
  func purgeCancelsAndPreventsAnOldFetchFromRepopulatingMemory() async throws {
    let store = RemoteArtworkDataStore(maximumByteCount: 1_024)
    let probe = ArtworkFetchProbe(data: Data(repeating: 3, count: 128), delay: .seconds(10))
    let url = URL(string: "https://artwork.example.test/private.jpg")!
    let load = Task {
      try await store.data(for: url) { try await probe.fetch() }
    }
    while await probe.fetchCount == 0 {
      await Task.yield()
    }

    await store.removeAll()

    await #expect(throws: CancellationError.self) {
      try await load.value
    }
    let cachedByteCount = await store.cachedByteCount
    let cachedEntryCount = await store.cachedEntryCount
    #expect(cachedByteCount == 0)
    #expect(cachedEntryCount == 0)
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

  @Test
  func decodedCacheReusesTheDownsampledImage() async throws {
    let decoded = RemoteArtworkDecodedStore(maximumEntryCount: 4)
    let url = URL(string: "https://artwork.example.test/reuse.jpg?token=first")!
    let renewedURL = URL(string: "https://artwork.example.test/reuse.jpg?token=renewed")!
    let image = try RemoteArtworkLoader.downsample(
      data: jpegData(width: 40, height: 40, orientation: .up),
      maxPixelDimension: 32
    )

    let generation = await decoded.generation
    await decoded.insert(image, for: url, maxPixelDimension: 32, generation: generation)
    let cached = await decoded.image(for: renewedURL, maxPixelDimension: 32)

    #expect(cached?.cgImage.width == image.cgImage.width)
    #expect(cached?.cgImage.height == image.cgImage.height)
  }

  @Test
  func purgeRejectsDecodedImageFromAnEarlierLoad() async throws {
    let decoded = RemoteArtworkDecodedStore()
    let url = URL(string: "https://artwork.example.test/private.jpg")!
    let image = try RemoteArtworkLoader.downsample(
      data: jpegData(width: 40, height: 40, orientation: .up),
      maxPixelDimension: 32
    )
    let generation = await decoded.generation

    await decoded.removeAll()
    await decoded.insert(image, for: url, maxPixelDimension: 32, generation: generation)

    #expect(await decoded.image(for: url, maxPixelDimension: 32)?.cgImage.width == nil)
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

private actor ArtworkFetchProbe {
  private let data: Data
  private let delay: Duration
  private(set) var fetchCount = 0

  init(data: Data, delay: Duration = .milliseconds(50)) {
    self.data = data
    self.delay = delay
  }

  func fetch() async throws -> Data {
    fetchCount += 1
    try await Task.sleep(for: delay)
    return data
  }
}

private actor ArtworkFetchGate {
  private let data: Data
  private var continuation: CheckedContinuation<Data, Error>?
  private(set) var fetchCount = 0

  init(data: Data) {
    self.data = data
  }

  func fetch() async throws -> Data {
    fetchCount += 1
    return try await withCheckedThrowingContinuation(isolation: self) { continuation in
      self.continuation = continuation
    }
  }

  func finish() {
    continuation?.resume(returning: data)
    continuation = nil
  }
}

private final class NeverCompletingArtworkURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {}

  override func stopLoading() {}
}
