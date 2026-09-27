import Foundation

struct OAuthProvider: Decodable, Sendable {
  let name: String
  let authURL: String
  let codeVerifier: String

  func authorizationURL(redirectURL: URL, clientID: String) throws -> URL {
    guard !clientID.isEmpty,
      var components = URLComponents(string: authURL + redirectURL.absoluteString),
      components.scheme == "https"
    else {
      throw OAuthError.invalidResponse
    }
    var queryItems = components.queryItems ?? []
    guard queryItems.contains(where: { $0.name == "redirect_uri" }) else {
      throw OAuthError.invalidResponse
    }
    queryItems.removeAll { $0.name == "state" }
    queryItems.append(URLQueryItem(name: "state", value: clientID))
    components.queryItems = queryItems
    guard let url = components.url else { throw OAuthError.invalidResponse }
    return url
  }
}

enum OAuthError: Error, Equatable {
  case unavailable
  case invalidResponse
  case disconnected
  case denied
  case presentationFailed
}

enum OAuthRealtimeEvent: Sendable, Equatable {
  case connected(String)
  case callback(OAuthCallback)
}

struct OAuthCallback: Decodable, Sendable, Equatable {
  let state: String?
  let code: String?
  let error: String?
}

struct OAuthSSEParser {
  private var event = ""
  private var id = ""
  private var data: [String] = []
  private var dataByteCount = 0

  mutating func consume(_ line: String) throws -> OAuthRealtimeEvent? {
    if line.isEmpty {
      defer {
        event = ""
        id = ""
        data = []
        dataByteCount = 0
      }
      switch event {
      case "PB_CONNECT":
        guard !id.isEmpty else { throw OAuthError.invalidResponse }
        return .connected(id)
      case "@oauth2":
        guard !data.isEmpty,
          let payload = data.joined(separator: "\n").data(using: .utf8),
          let callback = try? JSONDecoder().decode(OAuthCallback.self, from: payload)
        else { throw OAuthError.invalidResponse }
        return .callback(callback)
      default:
        return nil
      }
    }
    if line.hasPrefix(":") { return nil }
    let pieces = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard pieces.count == 2 else { return nil }
    let value = String(pieces[1].hasPrefix(" ") ? pieces[1].dropFirst() : pieces[1][...])
    switch pieces[0] {
    case "event": event = value
    case "id": id = value
    case "data":
      dataByteCount += value.utf8.count
      guard dataByteCount <= 8_192 else { throw OAuthError.invalidResponse }
      data.append(value)
    default: break
    }
    return nil
  }
}

enum OAuthRealtime {
  struct Connection: Sendable {
    let events: AsyncThrowingStream<OAuthRealtimeEvent, Error>
    private let stop: @Sendable () -> Void

    init(events: AsyncThrowingStream<OAuthRealtimeEvent, Error>, stop: @escaping @Sendable () -> Void) {
      self.events = events
      self.stop = stop
    }

    func cancel() { stop() }
  }

  static func open(url: URL, session: URLSession) -> Connection {
    let (events, continuation) = AsyncThrowingStream<OAuthRealtimeEvent, Error>.makeStream()
    let task = Task {
      do {
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200
        else { throw OAuthError.disconnected }
        var parser = OAuthSSEParser()
        var lineBytes = Data()
        for try await byte in bytes {
          try Task.checkCancellation()
          if byte != 10 {
            lineBytes.append(byte)
            guard lineBytes.count <= 8_192 else { throw OAuthError.invalidResponse }
            continue
          }
          if lineBytes.last == 13 { lineBytes.removeLast() }
          guard let line = String(data: lineBytes, encoding: .utf8) else {
            throw OAuthError.invalidResponse
          }
          lineBytes.removeAll(keepingCapacity: true)
          if let event = try parser.consume(line) {
            continuation.yield(event)
          }
        }
        throw OAuthError.disconnected
      } catch is CancellationError {
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }
    continuation.onTermination = { @Sendable _ in task.cancel() }
    return Connection(events: events) { task.cancel() }
  }
}
