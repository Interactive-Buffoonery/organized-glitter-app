import Foundation
import Testing
@testable import OrganizedGlitter

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct SpinHistoryTests {
  private let verticals = VerticalPreferences(diamondPainting: true, coloringBooks: true)

  @Test(arguments: RandomizerMode.allCases)
  func wireBodyPreservesFrozenIDsAndMode(mode: RandomizerMode) async throws {
    let library = try await makeLibrary()
    let selection = try draw(library, mode: mode)
    let data = try JSONEncoder().encode(SpinHistoryCreate(selection: selection,
      userID: library.userID, completedAt: Date(timeIntervalSince1970: 0)))
    let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(body["user"] as? String == "feature-user")
    #expect(body["selected_projects"] as? [String] == selection.candidates.map(\.item.recordID))
    #expect(body["selected_count"] as? Int == selection.candidates.count)
    #expect(body["id"] == nil)
    #expect((body["project"] as? String) == (mode == .diamond ? "project" : nil))
    let metadata = try #require(body["metadata"] as? [String: Any])
    #expect(metadata["version"] as? Int == 1)
    #expect(metadata["mode"] as? String == mode.spinWireValue)
    #expect(metadata["section"] == nil)
    let target = try #require(metadata["target"] as? [String: Any])
    #expect(target["targetType"] as? String == mode.spinTargetType)
    #expect(target["id"] as? String == selection.winner.item.recordID)
    #expect(target["href"] as? String == [RandomizerMode.diamond: "/projects/project",
      .book: "/coloring/book", .page: "/coloring/book/pages/page"][mode])
    if mode == .page { #expect(body["project_title"] as? String == "Book, page 3") }
    let eligibility = try #require(metadata["eligibility"] as? [String: Any])
    #expect(eligibility["ownership"] as? String == "owned")
    #expect(eligibility["diamondStatuses"] as? [String] == ["progress"])
  }

  @Test func otherModeFiltersRemainFrozenInSavedMetadata() async throws {
    let library = try await makeLibrary()
    let model = LibraryRandomizer(library: library)
    var configured: [RandomizerMode: Set<String>] = [.book: [], .page: []]
    let id = try #require(model.beginSelection(mode: .diamond, verticals: verticals,
      eligibility: configured))
    configured[.book] = RandomizerMode.book.defaultStatuses
    let selection = try #require(model.finishSelection(id: id))
    let body = SpinHistoryCreate(selection: selection, userID: library.userID, completedAt: .now)
    #expect(body.metadata.eligibility.bookStatuses.isEmpty)
    #expect(body.metadata.eligibility.pageStatuses.isEmpty)
    #expect(body.metadata.eligibility.diamondStatuses == ["progress"])
  }

  @Test func malformedMetadataKeepsLegacyFallbackAndSafeNavigation() async throws {
    let library = try await makeLibrary()
    for metadata in ["null", "42", #"{"version":2,"target":{"id":"foreign","href":"https://example.invalid"}}"#,
      #"{"version":1,"mode":"coloring-book","target":{"id":"project","targetType":"diamond_project"}}"#] {
      let data = Data(Self.row.dropLast().appending(",\"metadata\":\(metadata)}").utf8)
      let row = try JSONDecoder().decode(SpinHistoryRecord.self, from: data)
      #expect(row.title == "Project")
      if row.mode == .diamond { #expect(library.spinHistoryTarget(row, verticals: verticals)?.recordID == "project") }
      else { #expect(library.spinHistoryTarget(row, verticals: verticals) == nil) }
    }
    let foreign = try JSONDecoder().decode(SpinHistoryRecord.self,
      from: Data(Self.row.replacingOccurrences(of: "feature-user", with: "other").utf8))
    #expect(library.spinHistoryTarget(foreign, verticals: verticals) == nil)
  }

  @Test func acknowledgedSaveDispatchesOnceAndSurvivesFailedRefresh() async throws {
    let library = try await makeLibrary()
    let selection = try draw(library)
    #expect(await library.recordSpin(selection: selection, completedAt: .now) == .saved("spin"))
    #expect(await library.recordSpin(selection: selection, completedAt: .now) == .saved("spin"))
    #expect(HistoryProtocol.postCount == 1)
    HistoryProtocol.getStatus = 500
    await library.loadSpinHistory()
    #expect(library.spinHistoryLoadState == .failed)
    #expect(library.spinHistory.map(\.id) == ["spin"])
    #expect(library.spinHistorySaveStates[selection.id] == .saved("spin"))
  }

  @Test func uncertainDispatchNeverReplaysPost() async throws {
    let library = try await makeLibrary()
    let selection = try draw(library)
    HistoryProtocol.postStatus = 500
    #expect(await library.recordSpin(selection: selection, completedAt: .now) == .unknown)
    await library.loadSpinHistory()
    #expect(await library.recordSpin(selection: selection, completedAt: .now) == .unknown)
    #expect(HistoryProtocol.postCount == 1)
    #expect(library.spinHistorySaveStates[selection.id] == .unknown)
  }

  @Test(arguments: [400, 403, 409])
  func confirmedRejectionNeverReplaysPost(status: Int) async throws {
    let library = try await makeLibrary()
    let selection = try draw(library)
    HistoryProtocol.postStatus = status
    #expect(await library.recordSpin(selection: selection, completedAt: .now) == .rejected)
    #expect(await library.recordSpin(selection: selection, completedAt: .now) == .rejected)
    #expect(HistoryProtocol.postCount == 1)
  }

  @Test func disabledCraftKeepsHistoryButDisablesNavigation() async throws {
    let library = try await makeLibrary()
    await library.loadSpinHistory()
    let row = try #require(library.spinHistory.first)
    #expect(library.spinHistoryTarget(row,
      verticals: VerticalPreferences(diamondPainting: false, coloringBooks: true)) == nil)
    #expect(library.spinHistory.count == 1)
  }

  @Test func offlinePickDoesNotDispatchOrQueueHistory() async throws {
    let library = try await makeLibrary(online: false)
    let selection = try draw(library)
    #expect(await library.recordSpin(selection: selection, completedAt: .now) == .notSent)
    #expect(HistoryProtocol.postCount == 0)
    #expect(try await library.store.pendingCount(scope: library.scope) == 0)
    #expect(selection.winner.title == "Project")
  }

  @Test func pausedCancelledAndForeignDrawsDoNotDispatch() async throws {
    let library = try await makeLibrary()
    let selection = try draw(library)
    let task = Task { await library.recordSpin(selection: selection, completedAt: .now) }
    task.cancel()
    #expect(await task.value == .rejected)
    library.pauseWrites()
    #expect(await library.recordSpin(selection: try draw(library), completedAt: .now) == .rejected)
    let other = try localFeatureLibrary(userID: "other")
    #expect(await other.recordSpin(selection: selection, completedAt: .now) == .rejected)
    #expect(HistoryProtocol.postCount == 0)
  }

  @Test func boundedOwnedReadClearsOnClose() async throws {
    let library = try await makeLibrary()
    await library.loadSpinHistory()
    #expect(library.spinHistory.map(\.id) == ["spin"])
    let url = try #require(HistoryProtocol.getURLs.last)
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(query.first { $0.name == "perPage" }?.value == "8")
    #expect(query.first { $0.name == "filter" }?.value == "user = \"feature-user\"")
    #expect(query.first { $0.name == "sort" }?.value == "-spun_at")
    await library.loadSpinHistory(limit: 50)
    #expect(library.spinHistoryLimit == 50)
    try await library.close(removingData: false)
    #expect(library.spinHistory.isEmpty)
    #expect(library.spinHistorySaveStates.isEmpty)
    await library.loadSpinHistory()
    #expect(library.spinHistory.isEmpty)
  }

  @Test func staleReadCannotRestoreHistoryAfterAccountCloses() async throws {
    let library = try await makeLibrary()
    HistoryProtocol.holdReads = true
    let read = Task { await library.loadSpinHistory() }
    while HistoryProtocol.pendingCount == 0 { await Task.yield() }
    try await library.close(removingData: false)
    HistoryProtocol.releaseFirst()
    await read.value
    #expect(library.spinHistory.isEmpty)
    #expect(library.spinHistoryLoadState == .idle)
  }

  @Test func overlappingReadCannotReplaceNewerBoundedResult() async throws {
    let library = try await makeLibrary()
    HistoryProtocol.holdReads = true
    let old = Task { await library.loadSpinHistory() }
    while HistoryProtocol.pendingCount == 0 { await Task.yield() }
    HistoryProtocol.holdReads = false
    await library.loadSpinHistory(limit: 50)
    HistoryProtocol.releaseFirst(body: "{\"page\":1,\"perPage\":8,\"totalPages\":0,\"totalItems\":0,\"items\":[]}")
    await old.value
    #expect(library.spinHistory.map(\.id) == ["spin"])
    #expect(library.spinHistoryLimit == 50)
  }

  @Test func readStartedBeforeSavePreservesAcknowledgedRow() async throws {
    let library = try await makeLibrary()
    HistoryProtocol.holdReads = true
    let read = Task { await library.loadSpinHistory() }
    while HistoryProtocol.pendingCount == 0 { await Task.yield() }
    let selection = try draw(library)
    HistoryProtocol.holdReads = false
    #expect(await library.recordSpin(selection: selection, completedAt: .now) == .saved("spin"))
    HistoryProtocol.releaseFirst(body: "{\"page\":1,\"perPage\":8,\"totalPages\":0,\"totalItems\":0,\"items\":[]}")
    await read.value
    #expect(library.spinHistory.map(\.id) == ["spin"])
  }

  @Test func duplicateWhilePostIsPendingDoesNotDispatchAgain() async throws {
    let library = try await makeLibrary()
    let selection = try draw(library)
    HistoryProtocol.holdPosts = true
    let save = Task { await library.recordSpin(selection: selection, completedAt: .now) }
    while HistoryProtocol.pendingCount == 0 { await Task.yield() }
    #expect(await library.recordSpin(selection: selection, completedAt: .now) == .saving)
    #expect(HistoryProtocol.postCount == 1)
    HistoryProtocol.releaseFirst()
    #expect(await save.value == .saved("spin"))
  }

  @Test(arguments: [false, true], [401, 403])
  func terminalAuthenticationFailureDrainsWritesAndPreservesPendingEdits(saving: Bool, status: Int) async throws {
    let library = try await makeLibrary()
    let selection = try draw(library)
    let key = LocalRecordKey(kind: .project, id: "project")
    _ = try await library.store.queueEdit(scope: library.scope, key: key,
      patch: ["title": .string("Pending title")])
    let operation = try #require(await library.store.pendingOperations(scope: library.scope).first)
    var recovered = false
    library.onAuthenticationFailure = {
      await library.waitForWrites()
      try? await library.close(removingData: false)
      recovered = true
    }
    HistoryProtocol.postStatus = status
    HistoryProtocol.getStatus = status
    if saving {
      #expect(await library.recordSpin(selection: selection, completedAt: .now) == .rejected)
      #expect(await library.recordSpin(selection: selection, completedAt: .now) == .rejected)
      #expect(HistoryProtocol.postCount == 1)
    } else { await library.loadSpinHistory() }
    #expect(recovered)
    #expect(!library.isActive)
    #expect(try await library.store.pendingOperations(scope: library.scope).first?.id == operation.id)
    #expect(try await library.store.entry(scope: library.scope, key: key)?.item.title == "Pending title")
  }

  @Test func acceptedWriteRefreshesCrossClientHistoryAtCurrentBound() async throws {
    let library = try await makeLibrary()
    await library.loadSpinHistory(limit: 50)
    HistoryProtocol.getURLs = []
    HistoryProtocol.getBody = "{\"page\":1,\"perPage\":50,\"totalPages\":1,\"totalItems\":2,\"items\":[\(Self.row),\(Self.row.replacingOccurrences(of: "\"spin\"", with: "\"remote\""))]}"
    #expect(await library.recordSpin(selection: try draw(library), completedAt: .now) == .saved("spin"))
    #expect(Set(library.spinHistory.map(\.id)) == ["spin", "remote"])
    let url = try #require(HistoryProtocol.getURLs.last)
    #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
      .first { $0.name == "perPage" }?.value == "50")
    #expect(HistoryProtocol.getURLs.count == 1)
    #expect(HistoryProtocol.postCount == 1)
  }

  @Test func automaticRefreshCannotReplaceNewerCrossClientRead() async throws {
    let library = try await makeLibrary()
    let selection = try draw(library)
    HistoryProtocol.holdReads = true
    let save = Task { await library.recordSpin(selection: selection, completedAt: .now) }
    while HistoryProtocol.pendingCount == 0 { await Task.yield() }
    #expect(library.spinHistorySaveStates[selection.id] == .saved("spin"))
    await library.waitForWrites()
    HistoryProtocol.holdReads = false
    let remote = Self.row.replacingOccurrences(of: "\"spin\"", with: "\"remote\"")
    HistoryProtocol.getBody = "{\"page\":1,\"perPage\":50,\"totalPages\":1,\"totalItems\":2,\"items\":[\(Self.row),\(remote)]}"
    await library.loadSpinHistory(limit: 50)
    HistoryProtocol.releaseFirst(body: "{\"page\":1,\"perPage\":8,\"totalPages\":0,\"totalItems\":0,\"items\":[]}")
    #expect(await save.value == .saved("spin"))
    #expect(Set(library.spinHistory.map(\.id)) == ["spin", "remote"])
    #expect(library.spinHistoryLimit == 50)
    #expect(HistoryProtocol.postCount == 1)
  }

  @Test func automaticRefreshFailureCannotRejectAcknowledgedWrite() async throws {
    let library = try await makeLibrary()
    HistoryProtocol.getStatus = 500
    let selection = try draw(library)
    #expect(await library.recordSpin(selection: selection, completedAt: .now) == .saved("spin"))
    #expect(library.spinHistoryLoadState == .failed)
    #expect(library.spinHistorySaveStates[selection.id] == .saved("spin"))
    #expect(library.spinHistory.map(\.id) == ["spin"])
    #expect(HistoryProtocol.getURLs.count == 1)
  }

  @Test func currentTargetReflectsImmediateLocalSaveBeforeReload() async throws {
    let library = try await makeLibrary(online: false)
    let key = LocalRecordKey(kind: .project, id: "project")
    #expect(library.randomizerTarget(id: key, mode: .diamond, verticals: verticals)?.title == "Project")
    let saved: DiamondProjectRecord = try await library.update(collection: "projects", id: "project",
      body: ["title": "Locally saved"])
    #expect(saved.title == "Locally saved")
    #expect(library.randomizerTarget(id: key, mode: .diamond, verticals: verticals)?.title == saved.title)
    try await library.close(removingData: false)
    #expect(library.randomizerTarget(id: key, mode: .diamond, verticals: verticals) == nil)
  }

  @Test func openingHistoryUsesCurrentOwnedProjectionAfterEditsAndParentRemoval() async throws {
    let library = try await makeLibrary()
    let key = LocalRecordKey(kind: .page, id: "page")
    #expect(library.randomizerTarget(id: key, mode: .page, verticals: verticals) != nil)
    _ = try await library.store.queueEdit(scope: library.scope,
      key: LocalRecordKey(kind: .project, id: "project"), patch: ["title": .string("Edited")])
    try await library.loadLocal()
    #expect(library.randomizerTarget(id: LocalRecordKey(kind: .project, id: "project"),
      mode: .diamond, verticals: verticals)?.title == "Edited")
    #expect(library.randomizerTarget(id: key, mode: .book, verticals: verticals) == nil)
    try await library.store.removeConfirmed(scope: library.scope,
      key: LocalRecordKey(kind: .book, id: "book"))
    try await library.loadLocal()
    #expect(library.randomizerTarget(id: key, mode: .page, verticals: verticals) == nil)
  }

  @Test func refreshStartedAfterAcknowledgementCannotEraseItWithStaleServerRows() async throws {
    let library = try await makeLibrary()
    HistoryProtocol.getBody = "{\"page\":1,\"perPage\":8,\"totalPages\":0,\"totalItems\":0,\"items\":[]}"
    let selection = try draw(library)
    #expect(await library.recordSpin(selection: selection, completedAt: .now) == .saved("spin"))
    #expect(library.spinHistory.map(\.id) == ["spin"])
    #expect(library.spinHistorySaveStates[selection.id] == .saved("spin"))
    #expect(HistoryProtocol.postCount == 1)
    await library.loadSpinHistory()
    #expect(library.spinHistory.isEmpty)
    #expect(library.spinHistorySaveStates[selection.id] == .saved("spin"))
  }

  private func draw(_ library: LibrarySession, mode: RandomizerMode = .diamond) throws -> RandomizerSelection {
    let model = LibraryRandomizer(library: library)
    let id = try #require(model.beginSelection(mode: mode, verticals: verticals))
    return try #require(model.finishSelection(id: id))
  }
  private func makeLibrary(online: Bool = true) async throws -> LibrarySession {
    HistoryProtocol.reset()
    HistoryProtocol.postStatus = 200
    HistoryProtocol.getStatus = 200
    HistoryProtocol.getURLs = []
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [HistoryProtocol.self]
    let keychain = KeychainSessionStore(service: "SpinHistoryTests.\(UUID().uuidString)")
    let client = PocketBaseClient(baseURL: URL(string: "https://spin-history.example.invalid")!,
      sessionStore: keychain, urlSession: URLSession(configuration: configuration))
    _ = try await client.signIn(identity: "fixture", password: "fixture")
    try keychain.clear()
    let library = LibrarySession(client: client, userID: "feature-user",
      store: try LocalLibraryStore.inMemory(), connectionAvailable: online)
    for item in [LibraryItem.diamond(featureProject("project", title: "Project", status: "progress")),
      .book(featureBook("book", title: "Book", status: "in_progress")),
      .page(featurePage("page", book: "book", number: 3, status: "in_progress"))] {
      try await library.store.ingest(item, scope: library.scope)
    }
    try await library.loadLocal()
    return library
  }
  nonisolated fileprivate static let row = #"{"id":"spin","user":"feature-user","project":"project","project_title":"Project","spun_at":"2026-10-14T12:00:00.000Z","selected_projects":["project"],"selected_count":1}"#
}

private final class HistoryProtocol: URLProtocol, @unchecked Sendable {
  private final class State: @unchecked Sendable {
    let lock = NSLock()
    var postCount = 0
    var postStatus = 200
    var getStatus = 200
    var getURLs: [URL] = []
    var getBody: String?
    var holdReads = false
    var holdPosts = false
    var pending: [(HistoryProtocol, Int, String)] = []
  }
  private static let state = State()
  static var postCount: Int { state.lock.withLock { state.postCount } }
  static var postStatus: Int {
    get { state.lock.withLock { state.postStatus } }
    set { state.lock.withLock { state.postStatus = newValue } }
  }
  static var getStatus: Int {
    get { state.lock.withLock { state.getStatus } }
    set { state.lock.withLock { state.getStatus = newValue } }
  }
  static var getURLs: [URL] {
    get { state.lock.withLock { state.getURLs } }
    set { state.lock.withLock { state.getURLs = newValue } }
  }
  static var getBody: String? {
    get { state.lock.withLock { state.getBody } }
    set { state.lock.withLock { state.getBody = newValue } }
  }
  static var holdReads: Bool {
    get { state.lock.withLock { state.holdReads } }
    set { state.lock.withLock { state.holdReads = newValue } }
  }
  static var holdPosts: Bool {
    get { state.lock.withLock { state.holdPosts } }
    set { state.lock.withLock { state.holdPosts = newValue } }
  }
  static var pendingCount: Int { state.lock.withLock { state.pending.count } }
  static func reset() {
    state.lock.withLock {
      state.getBody = nil
      state.postCount = 0
      state.holdReads = false
      state.holdPosts = false
      state.pending = []
    }
  }
  static func releaseFirst(body: String? = nil) {
    let pending = state.lock.withLock { state.pending.removeFirst() }
    pending.0.respond(status: pending.1, body: body ?? pending.2)
  }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}
  override func startLoading() {
    let response: (Int, String, Bool) = Self.state.lock.withLock {
      if request.url!.path.hasSuffix("auth-with-password") {
        return (200, #"{"token":"fixture-token","record":{"id":"feature-user","verified":true}}"#, false)
      } else if request.url!.path.hasSuffix("auth-refresh") {
        return (401, "{}", false)
      } else if request.httpMethod == "POST" {
        Self.state.postCount += 1
        return (Self.state.postStatus, SpinHistoryTests.row, Self.state.holdPosts)
      } else {
        Self.state.getURLs.append(request.url!)
        return (Self.state.getStatus,
          Self.state.getBody ?? "{\"page\":1,\"perPage\":8,\"totalPages\":1,\"totalItems\":1,\"items\":[\(SpinHistoryTests.row)]}", Self.state.holdReads)
      }
    }
    if response.2 {
      Self.state.lock.withLock { Self.state.pending.append((self, response.0, response.1)) }
    } else { respond(status: response.0, body: response.1) }
  }
  private func respond(status: Int, body: String) {
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
}
