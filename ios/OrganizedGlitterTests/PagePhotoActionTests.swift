import Foundation
import Testing

@testable import OrganizedGlitter

@MainActor
@Suite(.serialized)
struct PagePhotoActionTests {
  private func setup() async throws -> (LibrarySession, LibraryItemDetailModel) {
    PhotoActionURLProtocol.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PhotoActionURLProtocol.self]
    let client = PocketBaseClient(
      baseURL: URL(string: "https://photos.example.test")!,
      sessionStore: KeychainSessionStore(service: "PhotoActions.\(UUID().uuidString)"),
      urlSession: URLSession(configuration: configuration))
    await client.prepareOfflineSession(.init(token: "fixture-token", userID: "feature-user"))
    let library = LibrarySession(client: client, userID: "feature-user", store: try LocalLibraryStore.inMemory())
    let page = try PhotoActionURLProtocol.page()
    try await library.store.ingest(.book(featureBook("book", title: "Quiet Pages")), scope: library.scope)
    try await library.store.ingest(.page(page), scope: library.scope)
    let model = LibraryItemDetailModel(item: .page(page), library: library)
    #expect(await model.load())
    return (library, model)
  }

  @Test func mainPromotionPreservesNewServerAttachmentsAndCommitsLocally() async throws {
    let (library, model) = try await setup()
    PhotoActionURLProtocol.files.append("other-device.jpg")
    #expect(await model.setMainPagePhoto("second.jpg"))
    guard case .page(let page) = model.item else { Issue.record("Expected page"); return }
    #expect(page.photos == ["second.jpg", "first.jpg", "other-device.jpg"])
    let local: ColoringPageRecord = try library.record(collection: "coloring_pages", id: "page")
    #expect(local.photos == page.photos)
    #expect(PhotoActionURLProtocol.mutations.first?.url?.path == "/api/coloring/pages/page/main-photo")
    #expect(PhotoActionURLProtocol.mutations.first?.httpMethod == "POST")
    #expect(PhotoActionURLProtocol.bodies.first == ["filename": "second.jpg"])
    try await library.close(removingData: false)
  }

  @Test func alreadyMainKeepsCurrentServerOrder() async throws {
    let (library, model) = try await setup()
    #expect(await model.setMainPagePhoto("first.jpg"))
    guard case .page(let page) = model.item else { Issue.record("Expected page"); return }
    #expect(page.photos == ["first.jpg", "second.jpg"])
    #expect(PhotoActionURLProtocol.mutations.count == 1)
    try await library.close(removingData: false)
  }

  @Test func removalUsesOnlyPartialFieldAndKeepsOtherDeviceAdditions() async throws {
    let (library, model) = try await setup()
    PhotoActionURLProtocol.files.append("other-device.jpg")
    #expect(await model.deletePagePhoto("first.jpg"))
    #expect(PhotoActionURLProtocol.bodies.first == ["photos-": ["first.jpg"]])
    guard case .page(let page) = model.item else { Issue.record("Expected page"); return }
    #expect(page.photos == ["second.jpg", "other-device.jpg"])
    #expect(PhotoActionURLProtocol.mutations.first?.httpMethod == "PATCH")
    try await library.close(removingData: false)
  }

  @Test func staleMainSelectionRefreshesCurrentFilesWithoutRetrying() async throws {
    let (library, model) = try await setup()
    PhotoActionURLProtocol.files = ["first.jpg", "new.jpg"]
    #expect(!(await model.setMainPagePhoto("second.jpg")))
    #expect(model.mutationErrorMessage?.contains("Photo list changed") == true)
    #expect(model.unresolvedWriteState == nil)
    guard case .page(let page) = model.item else { Issue.record("Expected page"); return }
    #expect(page.photos == ["first.jpg", "new.jpg"])
    #expect(PhotoActionURLProtocol.mutations.count == 1)
    try await library.close(removingData: false)
  }

  @Test func deletingAlreadyRemovedAttachmentKeepsCurrentServerFiles() async throws {
    let (library, model) = try await setup()
    PhotoActionURLProtocol.files = ["second.jpg", "new.jpg"]
    #expect(await model.deletePagePhoto("first.jpg"))
    guard case .page(let page) = model.item else { Issue.record("Expected page"); return }
    #expect(page.photos == ["second.jpg", "new.jpg"])
    try await library.close(removingData: false)
  }

  @Test func pendingLocalEditBlocksPhotoMutation() async throws {
    let (library, model) = try await setup()
    _ = try await library.store.queueEdit(
      scope: library.scope, key: .init(kind: .page, id: "page"), patch: ["status": .string("in_progress")])
    #expect(!(await model.deletePagePhoto("first.jpg")))
    #expect(PhotoActionURLProtocol.mutations.isEmpty)
    #expect(model.mutationErrorMessage?.contains("pending changes") == true)
    try await library.close(removingData: false)
  }

  @Test func lostResponseBlocksAllWritesUntilPhotosAreRefreshedAndReviewed() async throws {
    let (library, model) = try await setup()
    PhotoActionURLProtocol.losesResponse = true
    PhotoActionURLProtocol.snapshotAvailable = false
    #expect(!(await model.deletePagePhoto("first.jpg")))
    #expect(model.unresolvedWriteState == .needsRefresh)
    #expect(model.mutationErrorMessage?.contains("Photo action") == true)
    #expect(model.mutationErrorMessage?.localizedCaseInsensitiveContains("upload") == false)
    #expect(!(await model.setMainPagePhoto("second.jpg")))
    #expect(!(await model.updateFields(["revealed_subject": "Garden"])))
    let otherModel = LibraryItemDetailModel(item: model.item, library: library)
    #expect(!(await otherModel.setMainPagePhoto("second.jpg")))
    #expect(otherModel.unresolvedWriteState == .needsRefresh)
    #expect(PhotoActionURLProtocol.mutations.count == 1)
    PhotoActionURLProtocol.snapshotAvailable = true
    #expect(await model.refreshUnresolvedWriteStatus())
    #expect(model.unresolvedWriteState == .refreshed)
    #expect(!(await model.setMainPagePhoto("second.jpg")))
    model.clearUnresolvedWriteRecovery()
    #expect(model.unresolvedWriteState == nil)
    guard case .page(let page) = model.item else { Issue.record("Expected page"); return }
    #expect(page.photos == ["second.jpg"])
    try await library.close(removingData: false)
  }

  @Test func offlineActionRequiresRefreshWithoutQueuingFiles() async throws {
    let (library, model) = try await setup()
    PhotoActionURLProtocol.offline = true
    #expect(!(await model.deletePagePhoto("first.jpg")))
    #expect(model.unresolvedWriteState == .needsRefresh)
    #expect(model.mutationErrorMessage?.contains("Photo action") == true)
    #expect(try await library.store.pendingOperations(scope: library.scope).isEmpty)
    try await library.close(removingData: false)
  }

  @Test func unknownUploadBlocksMainAndDelete() async throws {
    let (library, model) = try await setup()
    PhotoActionURLProtocol.losesResponse = true
    PhotoActionURLProtocol.snapshotAvailable = false
    let photo = ProcessedDetailPhoto(data: Data([1]), fileName: "new.jpg", contentType: "image/jpeg")
    #expect(!(await model.appendPagePhoto(photo)))
    let requests = PhotoActionURLProtocol.mutations.count
    #expect(model.unresolvedWriteState == .needsRefresh)
    #expect(!(await model.setMainPagePhoto("second.jpg")))
    #expect(!(await model.deletePagePhoto("first.jpg")))
    #expect(PhotoActionURLProtocol.mutations.count == requests)
    try await library.close(removingData: false)
  }

  @Test func reservedPageBlocksLocalEditsAndLateAccountResponseIsIgnored() async throws {
    let (library, model) = try await setup()
    PhotoActionURLProtocol.holdsResponse = true
    let save = Task {
      let result = await model.setMainPagePhoto("second.jpg")
      await PhotoActionURLProtocol.gate.complete()
      return result
    }
    guard await PhotoActionURLProtocol.gate.wait() else {
      Issue.record("Photo action completed before issuing its request")
      _ = await save.value
      try await library.close(removingData: false)
      return
    }
    do {
      let _: ColoringPageRecord = try await library.update(
        collection: "coloring_pages", id: "page", body: ["status": "in_progress"])
      Issue.record("Reserved page accepted a local edit")
    } catch {
      #expect((error as? LibrarySessionError)?.errorDescription == LibrarySessionError.pendingChanges.errorDescription)
    }
    await library.client.prepareOfflineSession(.init(token: "other-token", userID: "other-user"))
    PhotoActionURLProtocol.finishHeld()
    #expect(!(await save.value))
    guard case .page(let page) = model.item else { Issue.record("Expected page"); return }
    #expect(page.photos == ["first.jpg", "second.jpg"])
    #expect(PhotoActionURLProtocol.snapshotRequests == 0)
    let local: ColoringPageRecord = try library.record(collection: "coloring_pages", id: "page")
    #expect(local.photos == page.photos)
    try await library.close(removingData: false)
  }

  @Test func switchedAccountCannotMutateTheOldAccountPage() async throws {
    let (library, model) = try await setup()
    await library.client.prepareOfflineSession(.init(token: "other-token", userID: "other-user"))
    #expect(!(await model.deletePagePhoto("first.jpg")))
    #expect(PhotoActionURLProtocol.mutations.isEmpty)
    #expect(PhotoActionURLProtocol.snapshotRequests == 0)
    try await library.close(removingData: false)
  }
}

private final class PhotoActionURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var offline = false
  nonisolated(unsafe) static var holdsResponse = false
  nonisolated(unsafe) static var held: PhotoActionURLProtocol?
  nonisolated(unsafe) static var gate = PhotoActionGate()
  nonisolated(unsafe) static var files = ["first.jpg", "second.jpg"]
  nonisolated(unsafe) static var mutations: [URLRequest] = []
  nonisolated(unsafe) static var bodies: [NSDictionary] = []
  nonisolated(unsafe) static var losesResponse = false
  nonisolated(unsafe) static var snapshotAvailable = true
  nonisolated(unsafe) static var snapshotRequests = 0

  static func reset() {
    offline = false; holdsResponse = false; held = nil; gate = PhotoActionGate()
    files = ["first.jpg", "second.jpg"]
    mutations = []; bodies = []; losesResponse = false; snapshotAvailable = true; snapshotRequests = 0
  }

  static func page() throws -> ColoringPageRecord {
    try JSONDecoder().decode(ColoringPageRecord.self, from: JSONSerialization.data(withJSONObject: pageObject))
  }

  private static var pageObject: [String: Any] {
    ["id": "page", "book": "book", "page_number": 1, "status": "not_started", "photos": files,
      "created": "2026-09-01", "updated": "2026-09-02"]
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    if Self.offline { fail(); return }
    if request.url?.path == "/api/mobile/sync/snapshot" {
      Self.snapshotRequests += 1
      guard Self.snapshotAvailable else { fail(); return }
      respond([
        "version": 1, "projects": [], "coloringBooks": [["id": "book", "user": "feature-user",
          "title": "Quiet Pages", "status": "in_stash", "total_pages": 1,
          "created": "2026-09-01", "updated": "2026-09-01"]],
        "coloringPages": [Self.pageObject], "progressNotes": [], "coloringPageProgressNotes": [],
      ])
      return
    }
    Self.mutations.append(request)
    let data = request.httpBody ?? readBody()
    let body = (try? JSONSerialization.jsonObject(with: data)) as? NSDictionary ?? [:]
    Self.bodies.append(body)
    if request.httpMethod == "POST", let filename = body["filename"] as? String {
      guard Self.files.contains(filename) else { respond(["message": "Photo list changed"], status: 409); return }
      Self.files = [filename] + Self.files.filter { $0 != filename }
    } else if let removed = body["photos-"] as? [String] {
      Self.files.removeAll { removed.contains($0) }
    }
    if Self.holdsResponse {
      Self.held = self
      Task { await Self.gate.signal() }
      return
    }
    if Self.losesResponse { fail(); return }
    respond(Self.pageObject)
  }

  static func finishHeld() {
    held?.respond(pageObject)
    held = nil
  }

  private func readBody() -> Data {
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open(); defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count <= 0 { break }
      data.append(contentsOf: buffer.prefix(count))
    }
    return data
  }

  private func fail() { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)) }
  private func respond(_ object: [String: Any], status: Int = 200) {
    client?.urlProtocol(self, didReceive: HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: object))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

private actor PhotoActionGate {
  private var requested = false
  private var completed = false
  private var waiter: CheckedContinuation<Bool, Never>?
  func wait() async -> Bool {
    if requested { return true }
    if completed { return false }
    return await withCheckedContinuation { waiter = $0 }
  }
  func signal() {
    requested = true
    waiter?.resume(returning: true)
    waiter = nil
  }
  func complete() {
    completed = true
    waiter?.resume(returning: requested)
    waiter = nil
  }
}
