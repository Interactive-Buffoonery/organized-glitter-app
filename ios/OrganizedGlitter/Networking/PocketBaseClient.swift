import Foundation

actor PocketBaseClient {
  struct ExternalAuthAttempt: Sendable {
    fileprivate let sessionGeneration: Int
    fileprivate let authGeneration: Int
  }

  nonisolated let baseURL: URL
  private let sessionStore: KeychainSessionStore
  private let urlSession: URLSession
  private let artworkStore = PrivateArtworkStore()
  private let oauthEvents: @Sendable (URL, URLSession) -> AsyncThrowingStream<OAuthRealtimeEvent, Error>

  private var authentication: AuthenticatedSession?
  private var refreshTask: Task<AuthenticatedSession, Error>?
  private var refreshGeneration: Int?
  private var sessionGeneration = 0
  private var oauthGeneration = 0

  init(
    baseURL: URL,
    sessionStore: KeychainSessionStore,
    urlSession: URLSession? = nil,
    oauthEvents: @escaping @Sendable (URL, URLSession) -> AsyncThrowingStream<OAuthRealtimeEvent, Error> = OAuthRealtime.events
  ) {
    self.baseURL = baseURL
    self.sessionStore = sessionStore
    self.urlSession = urlSession ?? Self.makeEphemeralURLSession()
    self.oauthEvents = oauthEvents
  }

  func signIn(identity: String, password: String) async throws -> AuthenticatedSession {
    sessionGeneration &+= 1
    let generation = sessionGeneration
    struct Body: Encodable {
      let identity: String
      let password: String
    }

    let response: AuthResponse = try await request(
      path: "/api/collections/users/auth-with-password",
      method: "POST",
      body: Body(identity: identity, password: password),
      includesAuthentication: false
    )

    guard generation == sessionGeneration else { throw APIError.cancelled }
    guard response.record.verified == true else {
      throw APIError.emailUnverified
    }
    return try persist(response.session)
  }

  func oauthProviders() async throws -> [OAuthProvider] {
    struct Methods: Decodable {
      struct OAuth2: Decodable {
        let enabled: Bool
        let providers: [OAuthProvider]
      }
      let oauth2: OAuth2
    }

    let methods: Methods = try await request(
      path: "/api/collections/users/auth-methods",
      includesAuthentication: false
    )
    return methods.oauth2.enabled
      ? methods.oauth2.providers.filter { $0.name == "google" || $0.name == "discord" }
      : []
  }

  func signInWithOAuth(
    providerName: String,
    present: @MainActor @Sendable (URL) throws -> Void,
    dismissAccepted: @MainActor @Sendable () -> Void
  ) async throws -> AuthenticatedSession {
    let attempt = beginExternalAuthAttempt()
    guard let provider = try await oauthProviders().first(where: { $0.name == providerName }) else {
      throw OAuthError.unavailable
    }

    let stream = oauthEvents(baseURL.appending(path: "/api/realtime"), urlSession)
    var events = stream.makeAsyncIterator()
    guard case .connected(let clientID) = try await events.next() else {
      throw OAuthError.disconnected
    }
    try checkExternalAuthAttempt(attempt)

    struct Subscription: Encodable {
      let clientId: String
      let subscriptions = ["@oauth2"]
    }
    _ = try await send(
      path: "/api/realtime",
      method: "POST",
      body: Subscription(clientId: clientID),
      includesAuthentication: false
    )
    try checkExternalAuthAttempt(attempt)

    let redirectURL = baseURL.appending(path: "/api/oauth2-redirect")
    let authorizationURL = try provider.authorizationURL(
      redirectURL: redirectURL,
      clientID: clientID
    )
    try await present(authorizationURL)

    while let event = try await events.next() {
      try checkExternalAuthAttempt(attempt)
      switch event {
      case .connected:
        throw OAuthError.disconnected
      case .callback(let callback):
        guard callback.state == clientID else { throw OAuthError.invalidResponse }
        guard callback.error == nil else { throw OAuthError.denied }
        guard let code = callback.code, !code.isEmpty else {
          throw OAuthError.invalidResponse
        }
        await dismissAccepted()
        struct Exchange: Encodable {
          let provider: String
          let code: String
          let codeVerifier: String
          let redirectUrl: String
        }
        let response: AuthResponse = try await request(
          path: "/api/collections/users/auth-with-oauth2",
          method: "POST",
          body: Exchange(
            provider: provider.name,
            code: code,
            codeVerifier: provider.codeVerifier,
            redirectUrl: redirectURL.absoluteString
          ),
          includesAuthentication: false
        )
        return try acceptExternalAuthResponse(response, attempt: attempt)
      }
    }
    throw OAuthError.disconnected
  }

  func beginExternalAuthAttempt() -> ExternalAuthAttempt {
    oauthGeneration &+= 1
    return ExternalAuthAttempt(
      sessionGeneration: sessionGeneration,
      authGeneration: oauthGeneration
    )
  }

  func cancelExternalAuthAttempt() {
    oauthGeneration &+= 1
  }

  func acceptExternalAuthResponse(
    _ response: AuthResponse,
    attempt: ExternalAuthAttempt
  ) throws -> AuthenticatedSession {
    guard response.record.verified == true else { throw APIError.emailUnverified }
    try checkExternalAuthAttempt(attempt)
    return try persist(response.session)
  }

  private func checkExternalAuthAttempt(_ attempt: ExternalAuthAttempt) throws {
    try Task.checkCancellation()
    guard attempt.authGeneration == oauthGeneration,
      attempt.sessionGeneration == sessionGeneration
    else {
      throw APIError.cancelled
    }
  }

  func register(email: String, username: String, password: String) async throws {
    struct Body: Encodable {
      let email: String
      let username: String
      let password: String
      let passwordConfirm: String
      let betaTester = true

      enum CodingKeys: String, CodingKey {
        case email, username, password, passwordConfirm
        case betaTester = "beta_tester"
      }
    }

    let _: UserRecord = try await request(
      path: "/api/collections/users/records",
      method: "POST",
      body: Body(
        email: email,
        username: username,
        password: password,
        passwordConfirm: password
      ),
      includesAuthentication: false
    )
  }

  func requestVerification(email: String) async throws {
    struct Body: Encodable {
      let email: String
    }

    _ = try await send(
      path: "/api/collections/users/request-verification",
      method: "POST",
      body: Body(email: email),
      includesAuthentication: false
    )
  }

  func requestPasswordReset(email: String) async throws {
    struct Body: Encodable {
      let email: String
    }

    _ = try await send(
      path: "/api/collections/users/request-password-reset",
      method: "POST",
      body: Body(email: email),
      includesAuthentication: false
    )
  }

  func confirmPasswordReset(
    token: String,
    password: String,
    passwordConfirmation: String
  ) async throws {
    struct Body: Encodable {
      let token: String
      let password: String
      let passwordConfirm: String
    }

    _ = try await send(
      path: "/api/collections/users/confirm-password-reset",
      method: "POST",
      body: Body(
        token: token,
        password: password,
        passwordConfirm: passwordConfirmation
      ),
      includesAuthentication: false
    )
  }

  func restore(_ stored: StoredSession) async throws -> AuthenticatedSession {
    prepareOfflineSession(stored)
    return try await refreshAuthentication()
  }

  func prepareOfflineSession(_ stored: StoredSession) {
    sessionGeneration &+= 1
    refreshTask?.cancel()
    refreshTask = nil
    refreshGeneration = nil
    authentication = AuthenticatedSession(
      token: stored.token,
      user: UserRecord(
        id: stored.userID,
        email: nil,
        verified: nil,
        username: nil,
        name: nil,
        avatar: nil,
        timezone: nil,
        themePreference: nil,
        created: nil,
        updated: nil
      )
    )

  }

  func refreshAuthentication() async throws -> AuthenticatedSession {
    if let refreshTask {
      guard let refreshGeneration else {
        throw APIError.server
      }
      return try acceptRefresh(
        try await refreshTask.value,
        generation: refreshGeneration
      )
    }

    guard let authentication else {
      throw APIError.unauthenticated
    }

    let generation = sessionGeneration
    let task = Task { [baseURL, urlSession] in
      var request = URLRequest(
        url: baseURL.appending(path: "/api/collections/users/auth-refresh")
      )
      request.httpMethod = "POST"
      request.cachePolicy = .reloadIgnoringLocalCacheData
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      request.setValue(authentication.token, forHTTPHeaderField: "Authorization")

      let data: Data
      let response: URLResponse
      do {
        (data, response) = try await urlSession.data(for: request)
      } catch {
        throw APIError.from(error)
      }

      guard let httpResponse = response as? HTTPURLResponse else {
        throw APIError.server
      }
      guard 200..<300 ~= httpResponse.statusCode else {
        throw APIError.from(statusCode: httpResponse.statusCode, body: data)
      }

      let authResponse: AuthResponse
      do {
        authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
      } catch {
        throw APIError.decoding
      }

      return authResponse.session
    }

    refreshTask = task
    refreshGeneration = generation
    defer {
      if refreshGeneration == generation {
        refreshTask = nil
        refreshGeneration = nil
      }
    }

    do {
      return try acceptRefresh(try await task.value, generation: generation)
    } catch {
      if generation == sessionGeneration,
        let apiError = error as? APIError,
        apiError == .unauthenticated || apiError == .forbidden
      {
        self.authentication = nil
      }
      throw error
    }
  }

  func signOut() {
    sessionGeneration &+= 1
    oauthGeneration &+= 1
    authentication = nil
    refreshTask?.cancel()
    refreshTask = nil
    refreshGeneration = nil
    try? sessionStore.clear()
  }

  func list<Record: Decodable & Sendable>(
    collection: String,
    page: Int = 1,
    perPage: Int = 50,
    filter: String? = nil,
    sort: String? = nil,
    expand: String? = nil
  ) async throws -> RecordList<Record> {
    var queryItems = [
      URLQueryItem(name: "page", value: String(page)),
      URLQueryItem(name: "perPage", value: String(perPage)),
    ]
    if let filter, !filter.isEmpty {
      queryItems.append(URLQueryItem(name: "filter", value: filter))
    }
    if let sort, !sort.isEmpty {
      queryItems.append(URLQueryItem(name: "sort", value: sort))
    }
    if let expand, !expand.isEmpty {
      queryItems.append(URLQueryItem(name: "expand", value: expand))
    }

    return try await request(
      path: "/api/collections/\(collection)/records",
      queryItems: queryItems
    )
  }

  func get<Record: Decodable & Sendable>(
    collection: String,
    id: String,
    expand: String? = nil
  ) async throws -> Record {
    let queryItems = expand.map { [URLQueryItem(name: "expand", value: $0)] } ?? []
    return try await request(
      path: "/api/collections/\(collection)/records/\(id)",
      queryItems: queryItems
    )
  }

  func allRecords<Record: Decodable & Sendable>(
    collection: String,
    filter: String? = nil,
    sort: String? = nil,
    expand: String? = nil
  ) async throws -> [Record] {
    var records: [Record] = []
    var page = 1
    var totalPages = 1

    repeat {
      let result: RecordList<Record> = try await list(
        collection: collection,
        page: page,
        filter: filter,
        sort: sort,
        expand: expand
      )
      records.append(contentsOf: result.items)
      totalPages = result.totalPages
      page += 1
    } while page <= totalPages

    return records
  }

  func create<Record: Decodable & Sendable>(
    collection: String,
    body: some Encodable
  ) async throws -> Record {
    try await request(
      path: "/api/collections/\(collection)/records",
      method: "POST",
      body: body
    )
  }

  func create<Record: Decodable & Sendable>(
    collection: String,
    multipart: PocketBaseMultipartForm
  ) async throws -> Record {
    try await requestEncoded(
      path: "/api/collections/\(collection)/records",
      method: "POST",
      body: try PocketBaseRequestBody(multipart: multipart)
    )
  }

  func update<Record: Decodable & Sendable>(
    collection: String,
    id: String,
    body: some Encodable
  ) async throws -> Record {
    try await request(
      path: "/api/collections/\(collection)/records/\(id)",
      method: "PATCH",
      body: body
    )
  }

  func update<Record: Decodable & Sendable>(
    collection: String,
    id: String,
    multipart: PocketBaseMultipartForm
  ) async throws -> Record {
    try await requestEncoded(
      path: "/api/collections/\(collection)/records/\(id)",
      method: "PATCH",
      body: try PocketBaseRequestBody(multipart: multipart)
    )
  }

  func delete(collection: String, id: String) async throws {
    _ = try await send(
      path: "/api/collections/\(collection)/records/\(id)",
      method: "DELETE"
    )
  }

  func mobileSnapshot() async throws -> LocalFullSnapshot {
    try await request(path: "/api/mobile/sync/snapshot")
  }

  func applyLocalOperation(_ operation: LocalPendingOperation) async throws -> LibraryItem {
    struct Body: Encodable {
      let operationId: String
      let collection: String
      let recordId: String
      let base: [String: LocalJSONValue]
      let patch: [String: LocalJSONValue]
    }
    let body = Body(
      operationId: operation.id.uuidString, collection: operation.key.kind.rawValue,
      recordId: operation.key.id, base: operation.base, patch: operation.patch)
    let result = try await sendResponseEncoded(
      path: "/api/mobile/sync/apply", method: "POST",
      body: PocketBaseRequestBody(json: body), acceptedStatusCodes: [409])
    let object = try JSONSerialization.jsonObject(with: result.data) as? [String: Any]
    guard let object else { throw APIError.decoding }
    if result.status == 409 {
      guard object["reason"] as? String == "field_conflict" else {
        throw APIError.validation("This edit could not be retried safely.")
      }
    }
    guard let recordObject = object["record"] else { throw APIError.decoding }
    let recordData = try JSONSerialization.data(withJSONObject: recordObject)
    let record: LibraryItem
    do {
      let decoder = JSONDecoder()
      switch operation.key.kind {
      case .project:
        record = .diamond(try decoder.decode(DiamondProjectRecord.self, from: recordData))
      case .book:
        record = .book(try decoder.decode(ColoringBookRecord.self, from: recordData))
      case .page:
        record = .page(try decoder.decode(ColoringPageRecord.self, from: recordData))
      }
    } catch {
      throw APIError.decoding
    }
    guard record.localRecordKey == operation.key else { throw APIError.decoding }
    if result.status == 409 { throw LocalSyncConflict(current: record) }
    return record
  }

  /// Fetches a short-lived token for protected file URLs.
  func fileToken() async throws -> String {
    struct Response: Decodable { let token: String }
    let response: Response = try await request(path: "/api/files/token", method: "POST")
    guard !response.token.isEmpty else { throw APIError.decoding }
    return response.token
  }

  /// Latest progress-note date per target, keyed by target id. `craft` is
  /// `diamond` (projects) or `coloring` (coloring pages); at most 100 ids.
  func latestNoteDates(craft: String, userID: String, targetIDs: [String]) async throws
    -> [String: String]
  {
    struct Body: Encodable {
      let userId: String
      let craft: String
      let targetIds: [String]
    }
    struct Response: Decodable {
      struct Item: Decodable {
        let targetId: String
        let date: String
      }
      let items: [Item]
    }
    guard !targetIDs.isEmpty else { return [:] }
    let response: Response = try await request(
      path: "/api/notes/latest",
      method: "POST",
      body: Body(userId: userID, craft: craft, targetIds: Array(targetIDs.prefix(100)))
    )
    return Dictionary(response.items.map { ($0.targetId, $0.date) }, uniquingKeysWith: max)
  }

  /// Builds an authenticated URL for a record's file field.
  nonisolated func fileURL(
    collection: String,
    recordID: String,
    filename: String,
    thumb: String? = nil,
    token: String
  ) -> URL {
    var url =
      baseURL
      .appending(path: "api/files")
      .appending(path: collection)
      .appending(path: recordID)
      .appending(path: filename)
    var queryItems = [URLQueryItem(name: "token", value: token)]
    if let thumb { queryItems.append(URLQueryItem(name: "thumb", value: thumb)) }
    url.append(queryItems: queryItems)
    return url
  }

  /// Empty-token URLs identify cached artwork and never authorize a download.
  func fileData(at url: URL, maximumByteCount: Int) async throws -> Data {
    guard let authentication else { throw APIError.unauthenticated }
    guard url.scheme == baseURL.scheme, url.host == baseURL.host, url.port == baseURL.port,
      url.path.hasPrefix(baseURL.appending(path: "api/files").path + "/")
    else { throw APIError.forbidden }
    let generation = sessionGeneration
    let scope = LocalAccountScope(backendURL: baseURL, userID: authentication.user.id)
    if let cached = try? await artworkStore.data(for: url, scope: scope) {
      guard generation == sessionGeneration else { throw APIError.cancelled }
      guard cached.count <= maximumByteCount else { throw RemoteArtworkError.payloadTooLarge }
      return cached
    }
    let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
      .first(where: { $0.name == "token" })?.value
    guard let token, !token.isEmpty else { throw APIError.offline }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue(authentication.token, forHTTPHeaderField: "Authorization")
    let fileURL: URL
    let response: URLResponse
    do {
      (fileURL, response) = try await urlSession.download(for: request)
    } catch { throw APIError.from(error) }
    defer { try? FileManager.default.removeItem(at: fileURL) }
    guard generation == sessionGeneration else { throw APIError.cancelled }
    guard let httpResponse = response as? HTTPURLResponse,
      response.url?.host == baseURL.host, response.url?.scheme == baseURL.scheme
    else { throw APIError.server }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw APIError.from(statusCode: httpResponse.statusCode, body: Data())
    }
    let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= maximumByteCount else { throw RemoteArtworkError.payloadTooLarge }
    let data = try Data(contentsOf: fileURL)
    try? await artworkStore.save(data, for: url, scope: scope)
    guard generation == sessionGeneration else { throw APIError.cancelled }
    return data
  }

  func retainDownloadedArtwork(
    items: [LibraryItem], notes: [DiamondProgressNoteRecord],
    coloringNotes: [ColoringProgressNoteRecord], scope: LocalAccountScope
  ) async throws {
    guard authentication?.user.id == scope.userID, scope.backendURL == baseURL else {
      throw APIError.unauthenticated
    }
    var urls: [URL] = []
    func include(_ collection: String, _ id: String, _ filenames: [String]) {
      for filename in filenames where !filename.isEmpty {
        for thumb in [nil, ArtworkThumb.gallery, ArtworkThumb.compact] as [String?] {
          urls.append(fileURL(collection: collection, recordID: id, filename: filename, thumb: thumb, token: ""))
        }
      }
    }
    for item in items {
      switch item {
      case .diamond(let record): include("projects", record.id, [record.image].compactMap { $0 })
      case .book(let record): include("coloring_books", record.id, [record.coverImage].compactMap { $0 })
      case .page(let record): include("coloring_pages", record.id, record.photos)
      }
    }
    for note in notes { include("progress_notes", note.id, [note.image].compactMap { $0 }) }
    for note in coloringNotes { include("coloring_page_progress_notes", note.id, [note.image].compactMap { $0 }) }
    try await artworkStore.retain(urls, scope: scope)
  }

  func removeDownloadedArtwork(scope: LocalAccountScope) async throws {
    try await artworkStore.remove(scope: scope)
  }

  private func persist(_ session: AuthenticatedSession) throws -> AuthenticatedSession {
    sessionGeneration &+= 1
    refreshTask?.cancel()
    refreshTask = nil
    refreshGeneration = nil
    try sessionStore.save(session)
    authentication = session
    return session
  }

  private func acceptRefresh(
    _ session: AuthenticatedSession,
    generation: Int
  ) throws -> AuthenticatedSession {
    guard generation == sessionGeneration, authentication != nil else {
      throw APIError.cancelled
    }
    try sessionStore.save(session)
    authentication = session
    return session
  }

  private static func makeEphemeralURLSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: configuration)
  }

  private func request<Response: Decodable>(
    path: String,
    queryItems: [URLQueryItem] = [],
    method: String = "GET",
    body: (any Encodable)? = nil,
    includesAuthentication: Bool = true
  ) async throws -> Response {
    try await requestEncoded(
      path: path,
      queryItems: queryItems,
      method: method,
      body: try body.map(PocketBaseRequestBody.init(json:)),
      includesAuthentication: includesAuthentication
    )
  }

  private func requestEncoded<Response: Decodable>(
    path: String,
    queryItems: [URLQueryItem] = [],
    method: String = "GET",
    body: PocketBaseRequestBody? = nil,
    includesAuthentication: Bool = true
  ) async throws -> Response {
    let data = try await sendEncoded(
      path: path,
      queryItems: queryItems,
      method: method,
      body: body,
      includesAuthentication: includesAuthentication
    )

    do {
      return try JSONDecoder().decode(Response.self, from: data)
    } catch {
      throw APIError.decoding
    }
  }

  private func send(
    path: String,
    queryItems: [URLQueryItem] = [],
    method: String = "GET",
    body: (any Encodable)? = nil,
    includesAuthentication: Bool = true,
    canRefreshAuthentication: Bool = true
  ) async throws -> Data {
    try await sendEncoded(
      path: path,
      queryItems: queryItems,
      method: method,
      body: try body.map(PocketBaseRequestBody.init(json:)),
      includesAuthentication: includesAuthentication,
      canRefreshAuthentication: canRefreshAuthentication
    )
  }

  private func sendEncoded(
    path: String,
    queryItems: [URLQueryItem] = [],
    method: String = "GET",
    body: PocketBaseRequestBody? = nil,
    includesAuthentication: Bool = true,
    canRefreshAuthentication: Bool = true
  ) async throws -> Data {
    try await sendResponseEncoded(
      path: path, queryItems: queryItems, method: method, body: body,
      includesAuthentication: includesAuthentication,
      canRefreshAuthentication: canRefreshAuthentication).data
  }

  private func sendResponseEncoded(
    path: String,
    queryItems: [URLQueryItem] = [],
    method: String = "GET",
    body: PocketBaseRequestBody? = nil,
    includesAuthentication: Bool = true,
    canRefreshAuthentication: Bool = true,
    acceptedStatusCodes: Set<Int> = []
  ) async throws -> (data: Data, status: Int) {
    let requestGeneration = sessionGeneration
    guard
      var components = URLComponents(
        url: baseURL.appending(path: path),
        resolvingAgainstBaseURL: false
      )
    else {
      throw APIError.server
    }
    components.queryItems = queryItems.isEmpty ? nil : queryItems
    guard let url = components.url else {
      throw APIError.server
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    if let body {
      request.httpBody = body.data
      request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
    }

    if includesAuthentication {
      guard let authentication else {
        throw APIError.unauthenticated
      }
      request.setValue(authentication.token, forHTTPHeaderField: "Authorization")
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await urlSession.data(for: request)
    } catch {
      throw APIError.from(error)
    }

    if includesAuthentication, requestGeneration != sessionGeneration {
      throw APIError.cancelled
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw APIError.server
    }

    if httpResponse.statusCode == 401,
      includesAuthentication,
      canRefreshAuthentication
    {
      _ = try await refreshAuthentication()
      return try await sendResponseEncoded(
        path: path,
        queryItems: queryItems,
        method: method,
        body: body,
        includesAuthentication: true,
        canRefreshAuthentication: false,
        acceptedStatusCodes: acceptedStatusCodes
      )
    }

    guard 200..<300 ~= httpResponse.statusCode
      || acceptedStatusCodes.contains(httpResponse.statusCode)
    else {
      throw APIError.from(
        statusCode: httpResponse.statusCode,
        body: data,
        isPasswordAuthentication: method == "POST"
          && path == "/api/collections/users/auth-with-password"
          && !includesAuthentication
      )
    }
    return (data, httpResponse.statusCode)
  }
}

private struct PocketBaseRequestBody: Sendable {
  let data: Data
  let contentType: String

  init(json: any Encodable) throws {
    data = try JSONEncoder().encode(AnyEncodable(json))
    contentType = "application/json"
  }

  init(multipart: PocketBaseMultipartForm) throws {
    let encoded = try multipart.encoded()
    data = encoded.data
    contentType = encoded.contentType
  }
}

private struct AnyEncodable: Encodable {
  private let encodeValue: (Encoder) throws -> Void

  init(_ value: any Encodable) {
    encodeValue = value.encode
  }

  func encode(to encoder: Encoder) throws {
    try encodeValue(encoder)
  }
}
