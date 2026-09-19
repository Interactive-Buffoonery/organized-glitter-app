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
  private let dataStore: RemoteArtworkDataStore

  convenience init() {
    #if DEBUG
      self.init(
        session: Self.sessionForDebugRun(
          isFixtureRun: OverviewFixtureProtocol.scenario != nil
        ))
    #else
      self.init(session: Self.ephemeralSession())
    #endif
  }

  init(
    session: URLSession,
    dataStore: RemoteArtworkDataStore = RemoteArtworkDataStore()
  ) {
    self.session = session
    self.dataStore = dataStore
  }

  func load(from url: URL, maxPixelDimension: CGFloat) async throws -> RemoteArtworkImage {
    let data = try await dataStore.data(for: url) { [session] in
      try await Self.downloadData(from: url, using: session)
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

  func purgeMemoryCache() async {
    await dataStore.removeAll()
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

  #if DEBUG
    static func sessionForDebugRun(isFixtureRun: Bool) -> URLSession {
      isFixtureRun ? OverviewFixtureProtocol.session() : ephemeralSession()
    }
  #endif

  private static func downloadData(from url: URL, using session: URLSession) async throws -> Data {
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
    return data
  }

  private static func ephemeralSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: configuration)
  }
}

actor RemoteArtworkDataStore {
  private struct Entry {
    let data: Data
    var lastAccess: UInt64
  }

  private struct InFlightRequest {
    let id: UUID
    let generation: UInt64
    let task: Task<Data, Error>
    var waiters: [UUID: CheckedContinuation<Data, Error>]
  }

  private let maximumByteCount: Int
  private var entries: [URL: Entry] = [:]
  private var inFlightRequests: [URL: InFlightRequest] = [:]
  private var accessCounter: UInt64 = 0
  private var generation: UInt64 = 0
  private(set) var cachedByteCount = 0

  init(maximumByteCount: Int = 24 * 1_024 * 1_024) {
    self.maximumByteCount = max(0, maximumByteCount)
  }

  var cachedEntryCount: Int {
    entries.count
  }

  func inFlightWaiterCount(for url: URL) -> Int {
    inFlightRequests[url]?.waiters.count ?? 0
  }

  func data(
    for url: URL,
    fetch: @escaping @Sendable () async throws -> Data
  ) async throws -> Data {
    try Task.checkCancellation()
    if var entry = entries[url] {
      accessCounter &+= 1
      entry.lastAccess = accessCounter
      entries[url] = entry
      return entry.data
    }

    let requestID: UUID
    if let existing = inFlightRequests[url] {
      requestID = existing.id
    } else {
      let task = Task {
        try await fetch()
      }
      let request = InFlightRequest(
        id: UUID(),
        generation: generation,
        task: task,
        waiters: [:]
      )
      inFlightRequests[url] = request
      requestID = request.id
      Task {
        do {
          let data = try await task.value
          completeRequest(with: data, for: url, requestID: request.id)
        } catch {
          failRequest(with: error, for: url, requestID: request.id)
        }
      }
    }

    let waiterID = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation(isolation: self) { continuation in
        guard var request = inFlightRequests[url], request.id == requestID else {
          continuation.resume(throwing: CancellationError())
          return
        }
        request.waiters[waiterID] = continuation
        inFlightRequests[url] = request
      }
    } onCancel: {
      Task {
        await self.cancelWaiter(waiterID, for: url, requestID: requestID)
      }
    }
  }

  func removeAll() {
    generation &+= 1
    for request in inFlightRequests.values {
      request.task.cancel()
      for continuation in request.waiters.values {
        continuation.resume(throwing: CancellationError())
      }
    }
    inFlightRequests.removeAll()
    entries.removeAll()
    cachedByteCount = 0
  }

  private func cancelWaiter(_ waiterID: UUID, for url: URL, requestID: UUID) {
    guard var request = inFlightRequests[url], request.id == requestID else {
      return
    }
    guard let continuation = request.waiters.removeValue(forKey: waiterID) else {
      return
    }
    continuation.resume(throwing: CancellationError())
    if request.waiters.isEmpty {
      request.task.cancel()
      inFlightRequests[url] = nil
    } else {
      inFlightRequests[url] = request
    }
  }

  private func completeRequest(with data: Data, for url: URL, requestID: UUID) {
    guard let request = inFlightRequests[url], request.id == requestID else {
      return
    }
    inFlightRequests[url] = nil
    if request.generation == generation {
      insert(data, for: url)
    }
    for continuation in request.waiters.values {
      continuation.resume(returning: data)
    }
  }

  private func failRequest(with error: Error, for url: URL, requestID: UUID) {
    guard let request = inFlightRequests[url], request.id == requestID else {
      return
    }
    inFlightRequests[url] = nil
    for continuation in request.waiters.values {
      continuation.resume(throwing: error)
    }
  }

  private func insert(_ data: Data, for url: URL) {
    guard maximumByteCount > 0, data.count <= maximumByteCount else {
      return
    }
    if let previous = entries[url] {
      cachedByteCount -= previous.data.count
    }
    accessCounter &+= 1
    entries[url] = Entry(data: data, lastAccess: accessCounter)
    cachedByteCount += data.count

    while cachedByteCount > maximumByteCount,
      let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })
    {
      entries[oldest.key] = nil
      cachedByteCount -= oldest.value.data.count
    }
  }
}

private enum RemoteArtworkError: Error {
  case invalidImage
  case invalidPixelDimension
  case invalidResponse
}
