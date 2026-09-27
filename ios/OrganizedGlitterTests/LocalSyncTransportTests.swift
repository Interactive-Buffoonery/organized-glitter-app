import Foundation
import Testing

@testable import OrganizedGlitter

@Suite(.serialized)
struct LocalSyncTransportTests {
  @Test
  func applyUsesStableOperationIDAndDecodesUpdatedRecord() async throws {
    LocalSyncURLProtocol.status = 200
    LocalSyncURLProtocol.body = #"{"outcome":"updated","record":{"id":"project-1","user":"user-1","title":"Offline title","status":"wishlist","kit_category":"full","created":"2026-01-01 00:00:00.000Z","updated":"2026-01-01 00:00:00.000Z"}}"#
    let client = makeClient()
    await client.prepareOfflineSession(StoredSession(token: "example-token", userID: "user-1"))
    let operation = LocalPendingOperation(
      id: UUID(), key: LocalRecordKey(kind: .project, id: "project-1"),
      base: ["title": .string("Server title")],
      patch: ["title": .string("Offline title")])

    let result = try await client.applyLocalOperation(operation)
    #expect(result.title == "Offline title")
    let body = try #require(LocalSyncURLProtocol.requestBody)
    let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(object["operationId"] as? String == operation.id.uuidString)
    #expect(object["collection"] as? String == "projects")
    #expect(object["recordId"] as? String == "project-1")
    #expect((object["base"] as? [String: String])?["title"] == "Server title")
    #expect((object["patch"] as? [String: String])?["title"] == "Offline title")
  }

  @Test
  func directConflictReturnsCurrentRecord() async throws {
    LocalSyncURLProtocol.status = 409
    LocalSyncURLProtocol.body = #"{"reason":"field_conflict","record":{"id":"project-1","user":"user-1","title":"Other title","status":"wishlist","kit_category":"full","created":"2026-01-01 00:00:00.000Z","updated":"2026-01-01 00:00:00.000Z"}}"#
    let client = makeClient()
    await client.prepareOfflineSession(StoredSession(token: "example-token", userID: "user-1"))
    let operation = LocalPendingOperation(
      id: UUID(), key: LocalRecordKey(kind: .project, id: "project-1"),
      base: ["title": .string("Server title")],
      patch: ["title": .string("Offline title")])

    do {
      _ = try await client.applyLocalOperation(operation)
      Issue.record("Expected a conflict")
    } catch let conflict as LocalSyncConflict {
      #expect(conflict.current.title == "Other title")
    }
  }

  private func makeClient() -> PocketBaseClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LocalSyncURLProtocol.self]
    return PocketBaseClient(
      baseURL: URL(string: "https://data.example.test")!,
      sessionStore: KeychainSessionStore(service: "example.local-sync-tests"),
      urlSession: URLSession(configuration: configuration))
  }
}

private final class LocalSyncURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var status = 200
  nonisolated(unsafe) static var body = ""
  nonisolated(unsafe) static var requestBody: Data?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.requestBody = bodyData
    let response = HTTPURLResponse(
      url: request.url!, statusCode: Self.status,
      httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private var bodyData: Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while true {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { return data }
      data.append(buffer, count: count)
    }
  }
}
