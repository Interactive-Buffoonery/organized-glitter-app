import Foundation
import ImageIO
import SwiftUI

struct RemoteArtwork<Content: View>: View {
  let url: URL?
  let maxPixelDimension: CGFloat
  private let content: (AsyncImagePhase) -> Content

  @State private var phase = AsyncImagePhase.empty
  @State private var requestID = UUID()
  @State private var activeURL: URL?

  init(
    url: URL?,
    maxPixelDimension: CGFloat = 660,
    @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
  ) {
    self.url = url
    self.maxPixelDimension = maxPixelDimension
    self.content = content
  }

  var body: some View {
    content(phase)
      .task(id: url) {
        await load()
      }
  }

  @MainActor
  private func load() async {
    let currentRequestID = UUID()
    requestID = currentRequestID
    activeURL = url
    phase = .empty
    guard let url else {
      return
    }

    do {
      let artwork = try await RemoteArtworkLoader.shared.load(
        from: url,
        maxPixelDimension: maxPixelDimension
      )
      try Task.checkCancellation()
      guard requestID == currentRequestID, activeURL == url else {
        return
      }
      phase = .success(
        Image(decorative: artwork.cgImage, scale: 1, orientation: .up)
      )
    } catch is CancellationError {
      return
    } catch {
      guard requestID == currentRequestID, activeURL == url, !Task.isCancelled else {
        return
      }
      phase = .failure(error)
    }
  }
}

struct RemoteArtworkImage: @unchecked Sendable {
  let cgImage: CGImage
}

final class RemoteArtworkLoader: @unchecked Sendable {
  static let shared = RemoteArtworkLoader()

  private let session: URLSession

  convenience init() {
    self.init(session: Self.ephemeralSession())
  }

  init(session: URLSession) {
    self.session = session
  }

  func load(from url: URL, maxPixelDimension: CGFloat) async throws -> RemoteArtworkImage {
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(from: url)
    } catch let error as URLError where error.code == .cancelled {
      throw CancellationError()
    }

    guard
      let httpResponse = response as? HTTPURLResponse,
      (200..<300).contains(httpResponse.statusCode)
    else {
      throw RemoteArtworkError.invalidResponse
    }
    try Task.checkCancellation()

    let decodingTask = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      let image = try Self.downsample(data: data, maxPixelDimension: maxPixelDimension)
      try Task.checkCancellation()
      return image
    }
    return try await withTaskCancellationHandler {
      try await decodingTask.value
    } onCancel: {
      decodingTask.cancel()
    }
  }

  static func downsample(data: Data, maxPixelDimension: CGFloat) throws -> RemoteArtworkImage {
    guard maxPixelDimension.isFinite, maxPixelDimension >= 1 else {
      throw RemoteArtworkError.invalidPixelDimension
    }

    return try autoreleasepool {
      let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
      guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
        throw RemoteArtworkError.invalidImage
      }

      let thumbnailOptions = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelDimension.rounded(.up)),
        kCGImageSourceShouldCacheImmediately: true,
      ] as CFDictionary
      guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
        throw RemoteArtworkError.invalidImage
      }
      return RemoteArtworkImage(cgImage: image)
    }
  }

  private static func ephemeralSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: configuration)
  }
}

private enum RemoteArtworkError: Error {
  case invalidImage
  case invalidPixelDimension
  case invalidResponse
}
