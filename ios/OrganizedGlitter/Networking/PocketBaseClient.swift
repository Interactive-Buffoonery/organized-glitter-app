import Foundation

actor PocketBaseClient {
  private let baseURL: URL
  private let sessionStore: KeychainSessionStore
  private let urlSession: URLSession

  private var authentication: AuthenticatedSession?
  private var refreshTask: Task<AuthenticatedSession, Error>?
  private var refreshGeneration: Int?
  private var sessionGeneration = 0

  init(
    baseURL: URL,
    sessionStore: KeychainSessionStore,
    urlSession: URLSession? = nil
  ) {
    self.baseURL = baseURL
    self.sessionStore = sessionStore
    self.urlSession = urlSession ?? Self.makeEphemeralURLSession()
  }

  func signIn(identity: String, password: String) async throws -> AuthenticatedSession {
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

    guard response.record.verified == true else {
      throw APIError.emailUnverified
    }
    return try persist(response.session)
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

  func restore(_ stored: StoredSession) async throws -> AuthenticatedSession {
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

    return try await refreshAuthentication()
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

  func delete(collection: String, id: String) async throws {
    _ = try await send(
      path: "/api/collections/\(collection)/records/\(id)",
      method: "DELETE"
    )
  }

  /// Builds the URL for a record's file field.
  ///
  /// Contract status: file fields are currently unprotected, so tokenless URLs
  /// resolve — but the backend `docs/FILE_ACCESS_CONTRACT.md` (status: blocked
  /// by privacy audit, 2026-07-27) treats that as a native public-release
  /// blocker. When the backend migrates to protected fields plus short-lived
  /// file tokens, this method becomes `async` and attaches a token. Keep this
  /// the only place in the app that constructs file URLs.
  nonisolated func fileURL(
    collection: String,
    recordID: String,
    filename: String,
    thumb: String? = nil
  ) -> URL {
    var url =
      baseURL
      .appending(path: "api/files")
      .appending(path: collection)
      .appending(path: recordID)
      .appending(path: filename)
    if let thumb {
      url.append(queryItems: [URLQueryItem(name: "thumb", value: thumb)])
    }
    return url
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
    let data = try await send(
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
      request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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

    guard let httpResponse = response as? HTTPURLResponse else {
      throw APIError.server
    }

    if httpResponse.statusCode == 401,
      includesAuthentication,
      canRefreshAuthentication
    {
      _ = try await refreshAuthentication()
      return try await send(
        path: path,
        queryItems: queryItems,
        method: method,
        body: body,
        includesAuthentication: true,
        canRefreshAuthentication: false
      )
    }

    guard 200..<300 ~= httpResponse.statusCode else {
      throw APIError.from(statusCode: httpResponse.statusCode, body: data)
    }
    return data
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
