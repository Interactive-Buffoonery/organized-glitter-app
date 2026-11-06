import Foundation
import Testing

@testable import OrganizedGlitter

@Suite(.serialized)
struct StatsTests {
  @Test
  func summaryTilesRetainServerTotalsAndTime() throws {
    let decoder = JSONDecoder()
    let diamond = try decoder.decode(DiamondStatsSummary.self, from: Data(Self.diamond.utf8))
    let coloring = try decoder.decode(ColoringStatsSummary.self, from: Data(Self.coloring.utf8))
    #expect(diamond.tiles.map(\.title) == ["Finished in 2026", "All-time finished", "In progress", "In stash", "Wishlist", "Total kits"])
    #expect(coloring.tiles.map(\.title) == ["Pages finished in 2026", "All-time pages finished", "Active pages", "Books in stash", "Wishlist", "Total books"])
    #expect(diamond.tiles.map(\.value) == [0, 0, 0, 0, 0, 0])
    #expect(StatsGeneratedTime.date(from: diamond.generatedAt) != nil)
    #expect(StatsGeneratedTime.date(from: "invalid") == nil)
    #expect(StatsGeneratedTime.date(from: "2026-10-10T12:00:00.000Z") == StatsGeneratedTime.date(from: "2026-10-10T12:00:00Z"))
  }

  @Test
  func summaryScreenFetchesOnlyTwoSummaries() async throws {
    StatsURLProtocol.requests = []
    StatsURLProtocol.responses = [Self.diamond, Self.coloring]
    let client = Self.client()
    await client.prepareOfflineSession(Self.session)
    _ = try await client.statsSnapshot(year: 2026, userID: "test-user")
    #expect(StatsURLProtocol.requests.map(\.url?.path) == ["/api/stats/summary", "/api/stats/coloring/summary"])
  }

  @Test
  func completionsPreserveNullAndZeroAverages() throws {
    let value = try JSONDecoder().decode(StatsCompletions.self, from: Data(Self.completions.utf8))
    #expect(value.months[0].averageCompletionDays == nil)
    #expect(value.months[1].averageCompletionDays == 0)
    #expect(value.year == 2026)
    #expect(value.months[0].previousYearDelta == -1)
  }

  @Test
  func requiredMetricsAndInvalidTypesFailDecoding() {
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(DiamondStatsSummary.self, from: Data("{}".utf8))
    }
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(StatsCompletions.self, from: Data(Self.completions.replacingOccurrences(of: "\"count\":0", with: "\"count\":\"0\"").utf8))
    }
  }

  @Test
  func requestsUseAuthenticatedServerPathsAndCalendarYear() async throws {
    StatsURLProtocol.requests = []
    StatsURLProtocol.responses = [Self.diamond, Self.completions, Self.coloring, Self.completions]
    let client = Self.client()
    await client.prepareOfflineSession(Self.session)
    _ = try await client.diamondStatsSummary(year: 1900)
    _ = try await client.statsCompletions(year: 2100, coloring: false)
    _ = try await client.coloringStatsSummary(year: 2026)
    _ = try await client.statsCompletions(year: 2026, coloring: true)
    #expect(StatsURLProtocol.requests.map(\.url?.path) == [
      "/api/stats/summary", "/api/stats/completions",
      "/api/stats/coloring/summary", "/api/stats/coloring/completions",
    ])
    #expect(StatsURLProtocol.requests.map(\.url?.query) == ["year=1900", "year=2100", "year=2026", "year=2026"])
    #expect(StatsURLProtocol.requests.allSatisfy {
      $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Authorization") == "test-token"
    })
    await #expect(throws: APIError.validation("Choose a year from 1900 through 2100.")) {
      _ = try await client.diamondStatsSummary(year: 1899)
    }
    #expect(StatsURLProtocol.requests.count == 4)
  }

  @Test
  func unexpectedServerYearCannotBeShownAsRequestedYear() async throws {
    StatsURLProtocol.responses = [Self.diamond, Self.coloring]
    let client = Self.client()
    await client.prepareOfflineSession(Self.session)
    await #expect(throws: APIError.decoding) {
      _ = try await client.statsSnapshot(year: 2025, userID: "test-user")
    }
  }

  @Test
  func signOutDuringStatsRequestRejectsLateResult() async throws {
    StatsURLProtocol.requests = []
    StatsURLProtocol.responses = [Self.diamond]
    StatsURLProtocol.responseDelay = 0.1
    defer { StatsURLProtocol.responseDelay = 0 }
    let client = Self.client()
    await client.prepareOfflineSession(Self.session)
    let request = Task { try await client.statsSnapshot(year: 2026, userID: "test-user") }
    while StatsURLProtocol.requests.isEmpty { await Task.yield() }
    await client.signOut()
    await #expect(throws: APIError.cancelled) { try await request.value }
    #expect(StatsURLProtocol.requests.count == 1)
  }

  @Test
  func invalidTransportResponseFailsWithoutInventingZeros() async throws {
    StatsURLProtocol.responses = ["{}"]
    let client = Self.client()
    await client.prepareOfflineSession(Self.session)
    await #expect(throws: APIError.decoding) {
      _ = try await client.coloringStatsSummary(year: 2026)
    }
  }

  static let completions = #"{"generatedAt":"2026-10-10T12:00:00.000Z","year":2026,"total":0,"months":[{"month":1,"label":"Jan","count":0,"previousYearCount":1,"previousYearDelta":-1,"averageCompletionDays":null},{"month":2,"label":"Feb","count":0,"previousYearCount":0,"previousYearDelta":0,"averageCompletionDays":0}]}"#
  static let diamond = #"{"generatedAt":"2026-10-10T12:00:00.000Z","year":2026,"metrics":{"totalKits":0,"completedThisYear":0,"inProgress":0,"inStash":0,"allTimeCompleted":0,"wishlistSize":0},"statusBreakdown":{}}"#
  static let coloring = #"{"generatedAt":"2026-10-10T12:00:00.000Z","year":2026,"metrics":{"totalBooks":0,"completedPagesThisYear":0,"activePages":0,"inStash":0,"allTimeCompletedPages":0,"wishlistSize":0},"bookStatusBreakdown":{},"pageStatusBreakdown":{}}"#

  static var session: StoredSession {
    StoredSession(token: "test-token", userID: "test-user")
  }

  static func client() -> PocketBaseClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StatsURLProtocol.self]
    return PocketBaseClient(
      baseURL: URL(string: "https://example.test")!,
      sessionStore: KeychainSessionStore(service: "stats-tests.\(UUID().uuidString)"),
      urlSession: URLSession(configuration: configuration)
    )
  }
}

private final class StatsURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var requests: [URLRequest] = []
  nonisolated(unsafe) static var responses: [String] = []
  nonisolated(unsafe) static var responseDelay: TimeInterval = 0

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.requests.append(request)
    let body = Self.responses.removeFirst()
    if Self.responseDelay > 0 { Thread.sleep(forTimeInterval: Self.responseDelay) }
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@MainActor
struct StatsLoadModelTests {
  @Test
  func supersededAccountResultsCannotPublish() async throws {
    let model = StatsLoadModel()
    let first = try localFeatureLibrary(userID: "first")
    let second = try localFeatureLibrary(userID: "second")
    let gate = StatsTestGate()
    let snapshot = try StatsTests.snapshot()
    let old = Task {
      await model.load(library: first, year: 2026) { _, _ in
        await gate.wait()
        return snapshot
      }
    }
    while !model.isLoading { await Task.yield() }
    await model.load(library: second, year: 2025) { _, _ in throw APIError.offline }
    await gate.release()
    await old.value
    #expect(model.snapshot == nil)
    #expect(model.errorMessage == "Stats need a connection. Reconnect and try again.")
    #expect(!model.isLoading)
  }

  @Test
  func refreshFailureKeepsSameAccountSnapshotAsStale() async throws {
    let model = StatsLoadModel()
    let library = try localFeatureLibrary()
    let snapshot = try StatsTests.snapshot()
    await model.load(library: library, year: 2026) { _, _ in snapshot }
    await model.load(library: library, year: 2026) { _, _ in throw APIError.server }
    #expect(model.snapshot == snapshot)
    #expect(model.isStale)
    #expect(model.errorMessage != nil)
    await model.load(library: library, year: 2025) { _, _ in throw APIError.server }
    #expect(model.snapshot == nil)
  }

  @Test
  func cancellationLeavesNoErrorOrLoadingState() async throws {
    let model = StatsLoadModel()
    let library = try localFeatureLibrary()
    await model.load(library: library, year: 2026) { _, _ in throw CancellationError() }
    #expect(model.snapshot == nil)
    #expect(model.errorMessage == nil)
    #expect(!model.isLoading)
  }

  @Test
  func cancelledTaskCannotPublishLateSnapshot() async throws {
    let model = StatsLoadModel()
    let library = try localFeatureLibrary()
    let gate = StatsTestGate()
    let snapshot = try StatsTests.snapshot()
    let request = Task {
      await model.load(library: library, year: 2026) { _, _ in
        await gate.wait()
        return snapshot
      }
    }
    while !model.isLoading { await Task.yield() }
    request.cancel()
    await gate.release()
    await request.value
    #expect(model.snapshot == nil)
    #expect(model.errorMessage == nil)
    #expect(!model.isLoading)
  }

  @Test
  func closedSessionAndWrongAccountCannotReadStats() async throws {
    let library = try localFeatureLibrary()
    await #expect(throws: APIError.cancelled) {
      _ = try await library.statsSnapshot(year: 2026)
    }
    try await library.close(removingData: false)
    await #expect(throws: APIError.cancelled) {
      _ = try await library.statsSnapshot(year: 2026)
    }
  }
}

extension StatsTests {
  static func snapshot() throws -> StatsSnapshot {
    let decoder = JSONDecoder()
    return StatsSnapshot(
      diamond: try decoder.decode(DiamondStatsSummary.self, from: Data(diamond.utf8)),
      coloring: try decoder.decode(ColoringStatsSummary.self, from: Data(coloring.utf8)))
  }
}

private actor StatsTestGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private var released = false
  func wait() async {
    if released { return }
    await withCheckedContinuation { continuation = $0 }
  }
  func release() {
    released = true
    continuation?.resume()
    continuation = nil
  }
}
