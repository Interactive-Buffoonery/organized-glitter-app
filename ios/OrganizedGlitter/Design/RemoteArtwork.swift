import Foundation
import ImageIO
import SwiftUI

enum ArtworkThumb {
  static let gallery = "320x420"
  static let compact = "160x160"
}

private struct PocketBaseClientEnvironmentKey: EnvironmentKey {
  static let defaultValue: PocketBaseClient? = nil
}

extension EnvironmentValues {
  var pocketBaseClient: PocketBaseClient? {
    get { self[PocketBaseClientEnvironmentKey.self] }
    set { self[PocketBaseClientEnvironmentKey.self] = newValue }
  }
}

struct RemoteArtwork<Content: View>: View {
  @Environment(\.pocketBaseClient) private var client

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
    let urlChanged = url != activeURL
    activeURL = url
    if urlChanged {
      phase = .empty
    }
    guard let url else {
      phase = .empty
      return
    }

    do {
      let artwork = try await RemoteArtworkLoader.shared.load(
        from: url,
        maxPixelDimension: maxPixelDimension,
        client: client
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
  static let maximumDownloadByteCount = 24 * 1_024 * 1_024

  private let session: URLSession
  private let dataStore: RemoteArtworkDataStore
  private let decodedStore: RemoteArtworkDecodedStore

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
    dataStore: RemoteArtworkDataStore = RemoteArtworkDataStore(),
    decodedStore: RemoteArtworkDecodedStore = RemoteArtworkDecodedStore()
  ) {
    self.session = session
    self.dataStore = dataStore
    self.decodedStore = decodedStore
  }

  func load(
    from url: URL,
    maxPixelDimension: CGFloat,
    client: PocketBaseClient? = nil
  ) async throws -> RemoteArtworkImage {
    let pixelSize = Int(maxPixelDimension.rounded(.up))
    let decodedGeneration = await decodedStore.generation
    if let cached = await decodedStore.image(for: url, maxPixelDimension: pixelSize) {
      return cached
    }

    let fileClient: PocketBaseClient?
    #if DEBUG
      fileClient = OverviewFixtureProtocol.scenario == nil ? client : nil
    #else
      fileClient = client
    #endif

    let data = try await dataStore.data(for: url) { [session] in
      if let fileClient {
        return try await fileClient.fileData(
          at: url, maximumByteCount: Self.maximumDownloadByteCount)
      }
      return try await Self.downloadData(
        from: url, using: session, maximumByteCount: Self.maximumDownloadByteCount)
    }
    try Task.checkCancellation()

    let decodingTask = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      let image = try Self.downsample(data: data, maxPixelDimension: maxPixelDimension)
      try Task.checkCancellation()
      return image
    }
    let image = try await withTaskCancellationHandler {
      try await decodingTask.value
    } onCancel: {
      decodingTask.cancel()
    }
    await decodedStore.insert(
      image, for: url, maxPixelDimension: pixelSize, generation: decodedGeneration)
    return image
  }

  func purgeMemoryCache() async {
    await dataStore.removeAll()
    await decodedStore.removeAll()
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

  private static func downloadData(
    from url: URL,
    using session: URLSession,
    maximumByteCount: Int
  ) async throws -> Data {
    let fileURL: URL
    let response: URLResponse
    do {
      (fileURL, response) = try await session.download(from: url)
    } catch let error as URLError where error.code == .cancelled {
      throw CancellationError()
    }
    defer { try? FileManager.default.removeItem(at: fileURL) }

    guard
      let httpResponse = response as? HTTPURLResponse,
      (200..<300).contains(httpResponse.statusCode)
    else {
      throw RemoteArtworkError.invalidResponse
    }
    let size =
      (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
    guard size <= maximumByteCount else {
      throw RemoteArtworkError.payloadTooLarge
    }
    return try Data(contentsOf: fileURL)
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

enum RemoteArtworkError: Error {
  case invalidImage
  case invalidPixelDimension
  case invalidResponse
  case payloadTooLarge
}

actor RemoteArtworkDecodedStore {
  private struct Key: Hashable {
    let url: URL
    let maxPixelDimension: Int
  }

  private struct Entry {
    let image: RemoteArtworkImage
    var lastAccess: UInt64
  }

  private let maximumEntryCount: Int
  private var entries: [Key: Entry] = [:]
  private var accessCounter: UInt64 = 0
  private(set) var generation: UInt64 = 0

  init(maximumEntryCount: Int = 48) {
    self.maximumEntryCount = max(0, maximumEntryCount)
  }

  func image(for url: URL, maxPixelDimension: Int) -> RemoteArtworkImage? {
    let key = Key(url: url, maxPixelDimension: maxPixelDimension)
    guard var entry = entries[key] else {
      return nil
    }
    accessCounter &+= 1
    entry.lastAccess = accessCounter
    entries[key] = entry
    return entry.image
  }

  func insert(
    _ image: RemoteArtworkImage, for url: URL, maxPixelDimension: Int, generation: UInt64
  ) {
    guard generation == self.generation, maximumEntryCount > 0 else {
      return
    }
    accessCounter &+= 1
    entries[Key(url: url, maxPixelDimension: maxPixelDimension)] = Entry(
      image: image, lastAccess: accessCounter)
    while entries.count > maximumEntryCount,
      let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })
    {
      entries[oldest.key] = nil
    }
  }

  func removeAll() {
    generation &+= 1
    entries.removeAll()
  }
}
