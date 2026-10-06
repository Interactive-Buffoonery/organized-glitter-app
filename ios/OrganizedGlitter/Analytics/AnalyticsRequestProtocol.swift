import Foundation

final class AnalyticsNetworkGate: @unchecked Sendable {
  let id = UUID().uuidString
  private let lock = NSLock()
  private let endpoint: URL
  private var enabled = false
  let sessionConfiguration: URLSessionConfiguration

  init(host: URL, sessionConfiguration: URLSessionConfiguration = .ephemeral) {
    endpoint = host.appending(path: "batch")
    self.sessionConfiguration = sessionConfiguration
  }

  func setEnabled(_ enabled: Bool) {
    lock.withLock { self.enabled = enabled }
  }

  func allows(_ request: URLRequest) -> Bool {
    guard var components = request.url.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }),
      components.query?.isEmpty != false, components.fragment == nil
    else { return false }
    components.query = nil
    return lock.withLock {
      enabled && request.httpMethod == "POST" && components.url == endpoint
    }
  }
}

final class AnalyticsRequestProtocol: URLProtocol, URLSessionTaskDelegate, @unchecked Sendable {
  static let gateHeader = "X-Organized-Glitter-Analytics-Gate"
  private static let registryLock = NSLock()
  nonisolated(unsafe) private static var gates: [String: AnalyticsNetworkGate] = [:]
  private let taskLock = NSLock()
  private var forwardingTask: URLSessionDataTask?
  private var session: URLSession?
  private var stopped = false

  static func register(_ gate: AnalyticsNetworkGate) {
    registryLock.withLock { gates[gate.id] = gate }
  }

  static func unregister(_ gate: AnalyticsNetworkGate) {
    registryLock.withLock { _ = gates.removeValue(forKey: gate.id) }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let id = request.value(forHTTPHeaderField: Self.gateHeader),
      let gate = Self.registryLock.withLock({ Self.gates[id] }), gate.allows(request)
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
      return
    }
    var forwarded = request
    forwarded.setValue(nil, forHTTPHeaderField: Self.gateHeader)
    if let stream = forwarded.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var body = Data()
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count >= 0 else {
          client?.urlProtocol(self, didFailWithError: URLError(.cannotDecodeContentData))
          return
        }
        if count == 0 { break }
        body.append(buffer, count: count)
      }
      forwarded.httpBodyStream = nil
      forwarded.httpBody = body
    }
    let session = URLSession(configuration: gate.sessionConfiguration, delegate: self, delegateQueue: nil)
    let task = session.dataTask(with: forwarded) { [weak self] data, response, error in
      guard let self else { return }
      defer { session.finishTasksAndInvalidate() }
      guard !self.taskLock.withLock({ self.stopped }) else { return }
      if let error {
        self.client?.urlProtocol(self, didFailWithError: error)
      } else if let response {
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data { self.client?.urlProtocol(self, didLoad: data) }
        self.client?.urlProtocolDidFinishLoading(self)
      }
    }
    taskLock.withLock {
      self.session = session
      self.forwardingTask = task
      if stopped { task.cancel() } else { task.resume() }
    }
  }

  override func stopLoading() {
    taskLock.withLock {
      stopped = true
      forwardingTask?.cancel()
      session?.invalidateAndCancel()
      forwardingTask = nil
      session = nil
    }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
