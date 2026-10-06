#if DEBUG
  import Foundation
  import UIKit

  /// Isolated, fictional responses for Overview runtime review. Never contacts a server.
  final class OverviewFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let store = FixtureStore()
    static let offlineAfterSeedArgument = "-fixture-offline-after-seed"
    static let offlineAfterAccountLoadArgument = "-fixture-offline-after-account-load"

    static var offlineAfterSeed: Bool {
      scenario != nil && (ProcessInfo.processInfo.arguments.contains(offlineAfterSeedArgument)
        || ProcessInfo.processInfo.arguments.contains(offlineAfterAccountLoadArgument))
    }

    static var offlineSeedCompleted: Bool {
      offlineAfterSeed && (store.hasCompletedOfflineSeed
        || (ProcessInfo.processInfo.arguments.contains(offlineAfterAccountLoadArgument)
          && store.hasCompletedAccountSeed))
    }

    static var scenario: String? {
      let arguments = ProcessInfo.processInfo.arguments
      guard let index = arguments.firstIndex(of: "-overview-fixture"),
        arguments.indices.contains(index + 1)
      else {
        return arguments.contains("-ui-testing-authenticated") ? "populated" : nil
      }
      return arguments[index + 1]
    }

    private static let sharedSession: URLSession = {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [OverviewFixtureProtocol.self]
      return URLSession(configuration: configuration)
    }()

    static func session() -> URLSession { sharedSession }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
      guard let url = request.url else { return }
      if url.path == "/api/files/token" {
        respond(object: ["token": "fictional-file-token"])
        return
      }
      if url.path.contains("/api/files/") {
        if url.lastPathComponent == "missing.png" {
          respond(object: [:], status: 404)
          return
        }
        respond(data: Self.artwork(filename: url.lastPathComponent), type: "image/jpeg")
        return
      }
      if url.path.contains("/auth-with-password") {
        respond(object: [
          "token": "fictional-fixture-token",
          "record": ["id": "preview-user", "verified": true, "username": "Fictional crafter"],
        ])
        return
      }
      if Self.offlineSeedCompleted {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        return
      }
      let scenario = Self.scenario ?? "populated"
      if url.path == "/api/collections/users/confirm-password-reset" {
        if scenario == "reset-lost-connection" {
          client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
        } else if scenario == "reset-server-failure" {
          respond(object: ["message": "Fictional service failure"], status: 503)
        } else {
          respond(object: ["message": "Invalid or expired token"], status: 400)
        }
        return
      }
      if url.path == "/api/collections/users/request-password-reset" {
        respond(object: [:], status: 204)
        return
      }
      let collection = Self.collectionAndID(from: url)?.collection
      let isLibraryRequest = Self.contentCollections.contains(collection ?? "")
        || url.path == "/api/mobile/sync/snapshot"
        || url.path == "/api/mobile/sync/apply"
      if scenario == "loading", isLibraryRequest { return }
      if scenario == "error", isLibraryRequest {
        respond(object: ["message": "Fictional service failure"], status: 503)
        return
      }
      let response = Self.store.response(for: request, scenario: scenario)
      respond(object: response.object, status: response.status)
    }

    private static let contentCollections: Set<String> = [
      "projects", "coloring_books", "coloring_pages", "progress_notes",
    ]

    private static var diamondItems: [[String: Any]] {
      (1...5).map { index in
        var item: [String: Any] = [
          "id": "fictional-project-\(index)", "user": "preview-user",
          "title": index == 1 ? "Garden of stars" : "A small constellation, chapter \(index)",
          "status": "progress", "kit_category": "full",
          "image": index == 2 ? "" : index == 3 ? "missing.png" : "fictional-garden.png",
          "created": "2026-09-01", "updated": "2026-09-07 12:0\(index):00",
        ]
        if index == 1 {
          item["expand"] = ["company": ["id": "company-1", "name": "Fictional atelier"]]
        }
        return item
      } + [
        [
          "id": "fictional-wishlist-project", "user": "preview-user",
          "title": "Wishlist garden", "status": "wishlist", "kit_category": "full",
          "image": "fictional-garden.png", "created": "2026-09-01",
          "updated": "2026-09-04 12:00:00",
        ]
      ]
    }

    private static var bookItems: [[String: Any]] {
      [
        [
          "id": "fictional-book-1", "user": "preview-user",
          "title": "Moonlit meadows", "status": "in_progress", "total_pages": 24,
          "completed_pages": 6, "cover_image": "fictional-cover.png",
          "created": "2026-09-01", "updated": "2026-09-07 11:00:00",
          "expand": ["publisher": ["id": "pub-1", "name": "Fictional Press"]],
        ],
        [
          "id": "fictional-book-2", "user": "preview-user",
          "title": "A quiet coloring book", "status": "in_stash", "total_pages": 12,
          "cover_image": "", "created": "2026-09-01", "updated": "2026-09-06 11:00:00",
        ],
        [
          "id": "fictional-book-3", "user": "preview-user",
          "title": "Missing cover book", "status": "purchased", "total_pages": 8,
          "cover_image": "missing.png", "created": "2026-09-01",
          "updated": "2026-09-05 11:00:00",
        ],
        [
          "id": "fictional-wishlist-book", "user": "preview-user",
          "title": "Wishlist coloring book", "status": "wishlist", "total_pages": 20,
          "cover_image": "fictional-cover.png", "created": "2026-09-01",
          "updated": "2026-09-04 11:00:00",
        ],
      ]
    }

    private static var pageItems: [[String: Any]] {
      [
        [
          "id": "fictional-page", "book": "fictional-book-1", "page_number": 12,
          "status": "in_progress", "photos": ["fictional-page.png"],
          "revealed_subject": "A moonlit garden with a very long, winding path",
          "created": "2026-09-01", "updated": "2026-09-07 13:00:00",
          "expand": [
            "book": [
              "id": "fictional-book-1", "user": "preview-user",
              "title": "Moonlit meadows", "status": "in_progress", "total_pages": 24,
              "created": "2026-09-01", "updated": "2026-09-07 11:00:00",
            ]
          ],
        ],
        [
          "id": "fictional-page-2", "book": "fictional-book-1", "page_number": 3,
          "status": "not_started", "photos": [],
          "revealed_subject": "An empty page",
          "created": "2026-09-01", "updated": "2026-09-06 13:00:00",
          "expand": [
            "book": [
              "id": "fictional-book-1", "user": "preview-user",
              "title": "Moonlit meadows", "status": "in_progress", "total_pages": 24,
              "created": "2026-09-01", "updated": "2026-09-07 11:00:00",
            ]
          ],
        ],
      ]
    }

    private static var progressNoteItems: [[String: Any]] {
      [
        [
          "id": "fictional-note-1", "project": "fictional-project-1",
          "content": "Finished the first section.", "date": "2026-09-07",
          "image": "fictional-note.png", "created": "2026-09-07 14:00:00",
          "updated": "2026-09-07 14:00:00",
        ],
        [
          "id": "fictional-note-2", "project": "fictional-project-1",
          "content": "Colors are coming together.", "date": "2026-09-05",
          "created": "2026-09-05 14:00:00", "updated": "2026-09-05 14:00:00",
        ],
      ]
    }

    private static func collectionAndID(from url: URL) -> (collection: String, id: String?)? {
      let components = url.pathComponents
      guard let records = components.firstIndex(of: "records"), records > 0 else {
        return nil
      }
      let id = components.indices.contains(records + 1) ? components[records + 1] : nil
      return (components[records - 1], id)
    }

    private struct FixtureResponse {
      let object: [String: Any]
      let status: Int
    }

    private final class FixtureStore: @unchecked Sendable {
      private let lock = NSLock()
      private var scenario: String?
      private var collections: [String: [[String: Any]]] = [:]
      private var sequence = 0
      private var servedSnapshot = false
      private var servedUser = false
      private var servedSettings = false

      var hasCompletedAccountSeed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return servedUser && servedSettings
      }

      var hasCompletedOfflineSeed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return servedSnapshot && servedUser && servedSettings
      }

      func response(for request: URLRequest, scenario: String) -> FixtureResponse {
        lock.lock()
        defer { lock.unlock() }

        if self.scenario != scenario {
          reset(for: scenario)
        }
        if request.url?.path == "/api/notes/latest" {
          return latestNotes(request: request)
        }
        if request.url?.path == "/api/mobile/sync/snapshot" {
          servedSnapshot = true
          return FixtureResponse(object: [
            "version": 1,
            "projects": collections["projects"] ?? [],
            "coloringBooks": collections["coloring_books"] ?? [],
            "coloringPages": collections["coloring_pages"] ?? [],
            "progressNotes": collections["progress_notes"] ?? [],
            "coloringPageProgressNotes": collections["coloring_page_progress_notes"] ?? [],
          ], status: 200)
        }
        if request.url?.path == "/api/mobile/sync/apply" {
          return apply(request: request)
        }
        guard let url = request.url,
          let target = OverviewFixtureProtocol.collectionAndID(from: url)
        else {
          return FixtureResponse(object: ["message": "Unknown fixture request"], status: 404)
        }

        switch request.httpMethod ?? "GET" {
        case "GET":
          if let id = target.id {
            let response = get(collection: target.collection, id: id)
            if target.collection == "users", response.status == 200 { servedUser = true }
            return response
          }
          let response = list(collection: target.collection, url: url)
          if target.collection == "user_dashboard_settings", response.status == 200 {
            servedSettings = true
          }
          return response
        case "POST":
          return create(collection: target.collection, request: request)
        case "PATCH":
          guard let id = target.id else {
            return FixtureResponse(object: ["message": "Missing fixture record ID"], status: 400)
          }
          return update(collection: target.collection, id: id, request: request)
        case "DELETE":
          guard let id = target.id else {
            return FixtureResponse(object: ["message": "Missing fixture record ID"], status: 400)
          }
          return delete(collection: target.collection, id: id)
        default:
          return FixtureResponse(object: ["message": "Unsupported fixture request"], status: 405)
        }
      }

      private func reset(for scenario: String) {
        self.scenario = scenario
        sequence = 0
        servedSnapshot = false
        servedUser = false
        servedSettings = false
        let hasContent = scenario != "empty"
        let usesDesignData = scenario == "design" || scenario == "many-pages"
        collections = [
          "users": [
            [
              "id": "preview-user", "verified": true, "username": "Fictional crafter",
              "name": "Fictional crafter", "timezone": "America/New_York",
              "theme_preference": "system", "analytics_opt_out": false,
              "created": "2026-09-01 10:00:00",
              "updated": "2026-09-19 10:00:00",
            ]
          ],
          "user_dashboard_settings": [
            [
              "id": "fictional-settings", "user": "preview-user",
              "vertical_enabled": ["diamond_painting": true, "coloring_books": true],
            ]
          ],
          "projects": hasContent
            ? (usesDesignData
              ? OverviewFixtureProtocol.designDiamonds : OverviewFixtureProtocol.diamondItems) : [],
          "coloring_books": hasContent
            ? (usesDesignData
              ? OverviewFixtureProtocol.designBooks : OverviewFixtureProtocol.bookItems) : [],
          "coloring_pages": hasContent
            ? (usesDesignData
              ? OverviewFixtureProtocol.designPages : OverviewFixtureProtocol.pageItems) : [],
          "progress_notes": hasContent
            ? (usesDesignData
              ? OverviewFixtureProtocol.designProgressNotes
              : OverviewFixtureProtocol.progressNoteItems) : [],
          "coloring_page_progress_notes": hasContent && usesDesignData
            ? OverviewFixtureProtocol.designPageProgressNotes : [],
        ]
        if scenario == "many-pages", var books = collections["coloring_books"],
          var firstBook = books.first
        {
          firstBook["total_pages"] = 30
          books[0] = firstBook
          collections["coloring_books"] = books
          var pages = collections["coloring_pages"] ?? []
          for index in pages.indices {
            pages[index]["expand"] = ["book": firstBook]
          }
          for index in pages.count..<30 {
            pages.append([
              "id": "design-page-\(index)", "book": "design-book-0",
              "page_number": index + 1, "status": "not_started", "photos": [],
              "created": "2026-09-01", "updated": "2026-09-19 12:08:00",
              "expand": ["book": firstBook],
            ])
          }
          collections["coloring_pages"] = pages
        }
      }

      private func apply(request: URLRequest) -> FixtureResponse {
        let body = jsonValues(from: request)
        guard let collection = body["collection"] as? String,
          let id = body["recordId"] as? String,
          let patch = body["patch"] as? [String: Any],
          let base = body["base"] as? [String: Any],
          let index = collections[collection]?.firstIndex(where: { $0["id"] as? String == id })
        else {
          return FixtureResponse(object: ["message": "Fixture record not found"], status: 404)
        }
        var record = collections[collection]![index]
        for field in patch.keys {
          let current = (record[field] ?? NSNull()) as? NSObject
          let previous = (base[field] ?? NSNull()) as? NSObject
          if current != previous {
            return FixtureResponse(
              object: ["reason": "field_conflict", "record": record], status: 409)
          }
        }
        for (field, value) in patch { record[field] = value }
        record["updated"] = "2026-09-19 15:00:00"
        collections[collection]![index] = record
        return FixtureResponse(object: ["record": record], status: 200)
      }

      private func latestNotes(request: URLRequest) -> FixtureResponse {
        let body = jsonValues(from: request)
        let ids = body["targetIds"] as? [String] ?? []
        let notes = body["craft"] as? String == "diamond" ? collections["progress_notes"] ?? [] : []
        let items: [[String: Any]] = ids.compactMap { id in
          let dates = notes.filter { $0["project"] as? String == id }.compactMap { $0["date"] as? String }
          return dates.max().map { ["id": "latest-\(id)", "targetId": id, "date": $0, "created": $0] }
        }
        return FixtureResponse(object: ["items": items], status: 200)
      }

      private func get(collection: String, id: String) -> FixtureResponse {
        guard let record = collections[collection]?.first(where: { $0["id"] as? String == id }) else {
          return FixtureResponse(object: ["message": "Fixture record not found"], status: 404)
        }
        return FixtureResponse(object: record, status: 200)
      }

      private func list(collection: String, url: URL) -> FixtureResponse {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let filter = queryItems.first(where: { $0.name == "filter" })?.value ?? ""
        let sort = queryItems.first(where: { $0.name == "sort" })?.value ?? ""
        let requestedPage = Int(queryItems.first(where: { $0.name == "page" })?.value ?? "1") ?? 1
        let requestedPerPage = max(
          1,
          Int(queryItems.first(where: { $0.name == "perPage" })?.value ?? "50") ?? 50
        )
        let isBookPageRequest = collection == "coloring_pages" && filter.contains("book = \"")
        let perPage = isBookPageRequest && scenario == "design"
          ? min(requestedPerPage, 4) : requestedPerPage

        var items = (collections[collection] ?? []).filter {
          matches($0, collection: collection, filter: filter)
        }
        sortItems(&items, by: sort)

        let totalItems = items.count
        let totalPages = totalItems == 0 ? 0 : Int(ceil(Double(totalItems) / Double(perPage)))
        let start = max(0, (requestedPage - 1) * perPage)
        if start < totalItems {
          items = Array(items[start..<min(start + perPage, totalItems)])
        } else {
          items = []
        }
        return FixtureResponse(
          object: [
            "page": requestedPage, "perPage": perPage, "totalPages": totalPages,
            "totalItems": totalItems, "items": items,
          ],
          status: 200
        )
      }

      private func create(collection: String, request: URLRequest) -> FixtureResponse {
        let upload = multipart(from: request)
        var record = jsonValues(from: request)
        for (key, value) in upload.fields {
          record[key] = value
        }
        sequence += 1
        record["id"] = "fixture-\(collection)-\(sequence)"
        record["created"] = "2026-09-19 15:00:00"
        record["updated"] = "2026-09-19 15:00:00"

        switch collection {
        case "projects":
          record["status"] = record["status"] ?? "wishlist"
          record["kit_category"] = record["kit_category"] ?? "full"
        case "coloring_books":
          record["status"] = record["status"] ?? "in_stash"
          record["total_pages"] = record["total_pages"] ?? 1
          record["completed_pages"] = 0
        case "progress_notes", "coloring_page_progress_notes":
          record["content"] = record["content"] ?? ""
          if collection == "coloring_page_progress_notes" {
            record["user"] = "preview-user"
          }
          if let image = upload.files["image"]?.first {
            record["image"] = image
          }
        case "user_dashboard_settings":
          break
        default:
          return FixtureResponse(object: ["message": "Unsupported fixture create"], status: 400)
        }

        collections[collection, default: []].append(record)
        if collection == "coloring_books" {
          synchronizePages(for: record)
        }
        return FixtureResponse(object: record, status: 200)
      }

      private func update(
        collection: String,
        id: String,
        request: URLRequest
      ) -> FixtureResponse {
        guard let index = collections[collection]?.firstIndex(where: { $0["id"] as? String == id }) else {
          return FixtureResponse(object: ["message": "Fixture record not found"], status: 404)
        }
        var record = collections[collection]![index]
        let upload = multipart(from: request)
        for (key, value) in jsonValues(from: request) {
          record[key] = value
        }
        for (key, value) in upload.fields {
          record[key] = value
        }
        if collection == "coloring_pages" {
          var photos = record["photos"] as? [String] ?? []
          photos.append(contentsOf: upload.files["photos+"] ?? [])
          record["photos"] = photos
        }
        record["updated"] = "2026-09-19 15:00:00"
        collections[collection]![index] = record
        if collection == "coloring_books" {
          synchronizePages(for: record)
        }
        return FixtureResponse(object: record, status: 200)
      }

      private func delete(collection: String, id: String) -> FixtureResponse {
        guard collections[collection]?.contains(where: { $0["id"] as? String == id }) == true else {
          return FixtureResponse(object: ["message": "Fixture record not found"], status: 404)
        }
        collections[collection]?.removeAll { $0["id"] as? String == id }
        if collection == "projects" {
          collections["progress_notes"]?.removeAll { $0["project"] as? String == id }
        } else if collection == "coloring_books" {
          collections["coloring_pages"]?.removeAll { $0["book"] as? String == id }
        }
        return FixtureResponse(object: [:], status: 204)
      }

      private func jsonValues(from request: URLRequest) -> [String: Any] {
        if request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true {
          return [:]
        }
        guard let data = bodyData(from: request),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
          return [:]
        }
        return object
      }

      private func multipart(from request: URLRequest) -> (
        fields: [String: String], files: [String: [String]]
      ) {
        guard let contentType = request.value(forHTTPHeaderField: "Content-Type"),
          let boundaryRange = contentType.range(of: "boundary="),
          let data = bodyData(from: request)
        else {
          return ([:], [:])
        }
        let boundary = String(contentType[boundaryRange.upperBound...])
          .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let body = String(decoding: data, as: UTF8.self)
        var fields: [String: String] = [:]
        var files: [String: [String]] = [:]

        for rawPart in body.components(separatedBy: "--\(boundary)") {
          guard let separator = rawPart.range(of: "\r\n\r\n") else { continue }
          let headers = String(rawPart[..<separator.lowerBound])
          guard let name = quotedValue(named: "name", in: headers) else { continue }
          if let filename = quotedValue(named: "filename", in: headers) {
            files[name, default: []].append(filename)
          } else {
            let value = rawPart[separator.upperBound...]
              .trimmingCharacters(in: .whitespacesAndNewlines)
            fields[name] = value
          }
        }
        return (fields, files)
      }

      private func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
          return body
        }
        guard let stream = request.httpBodyStream else {
          return nil
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
          let count = stream.read(&buffer, maxLength: buffer.count)
          guard count > 0 else { break }
          data.append(buffer, count: count)
        }
        return data
      }

      private func quotedValue(named name: String, in string: String) -> String? {
        let marker = "\(name)=\""
        guard let start = string.range(of: marker) else { return nil }
        let remainder = string[start.upperBound...]
        guard let end = remainder.firstIndex(of: "\"") else { return nil }
        return String(remainder[..<end])
      }

      private func matches(
        _ item: [String: Any],
        collection: String,
        filter: String
      ) -> Bool {
        if let status = equalityValue(field: "status", in: filter),
          item["status"] as? String != status
        {
          return false
        }
        for relation in ["book", "project"] {
          if let value = equalityValue(field: relation, in: filter),
            item[relation] as? String != value
          {
            return false
          }
        }
        if let pageNumber = integerEqualityValue(field: "page_number", in: filter),
          item["page_number"] as? Int != pageNumber
        {
          return false
        }
        guard let search = containsValue(in: filter) else {
          return true
        }
        let searchable: [String]
        switch collection {
        case "projects":
          let expand = item["expand"] as? [String: Any]
          let company = expand?["company"] as? [String: Any]
          let artist = expand?["artist"] as? [String: Any]
          searchable = [item["title"], company?["name"], artist?["name"]]
            .compactMap { $0 as? String }
        case "coloring_books":
          searchable = [item["title"], item["series"]].compactMap { $0 as? String }
        case "coloring_pages":
          let expand = item["expand"] as? [String: Any]
          let book = expand?["book"] as? [String: Any]
          searchable = [item["revealed_subject"], book?["title"]].compactMap { $0 as? String }
        default:
          searchable = [item["content"]].compactMap { $0 as? String }
        }
        return searchable.contains { $0.localizedCaseInsensitiveContains(search) }
      }

      private func equalityValue(field: String, in filter: String) -> String? {
        quotedValue(after: "\(field) = \"", in: filter)
      }

      private func integerEqualityValue(field: String, in filter: String) -> Int? {
        guard let range = filter.range(of: "\(field) = ") else { return nil }
        let suffix = filter[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits)
      }

      private func containsValue(in filter: String) -> String? {
        quotedValue(after: "~ \"", in: filter)
      }

      private func quotedValue(after marker: String, in string: String) -> String? {
        guard let start = string.range(of: marker) else { return nil }
        let remainder = string[start.upperBound...]
        guard let end = remainder.firstIndex(of: "\"") else { return nil }
        return String(remainder[..<end])
          .replacingOccurrences(of: #"\""#, with: "\"")
          .replacingOccurrences(of: #"\\"#, with: "\\")
      }

      private func sortItems(_ items: inout [[String: Any]], by sort: String) {
        guard !sort.isEmpty else { return }
        let primarySort = String(sort.split(separator: ",").first ?? "")
        let descending = primarySort.hasPrefix("-")
        let field = String(primarySort.drop(while: { $0 == "+" || $0 == "-" }))
        items.sort { left, right in
          if field == "page_number" {
            let leftValue = left[field] as? Int ?? 0
            let rightValue = right[field] as? Int ?? 0
            return descending ? leftValue > rightValue : leftValue < rightValue
          }
          let key = field == "title_sort" ? "title" : field
          let leftValue = left[key] as? String ?? ""
          let rightValue = right[key] as? String ?? ""
          let comparison = leftValue.localizedCaseInsensitiveCompare(rightValue)
          return descending ? comparison == .orderedDescending : comparison == .orderedAscending
        }
      }

      private func synchronizePages(for book: [String: Any]) {
        guard let bookID = book["id"] as? String,
          let totalPages = book["total_pages"] as? Int
        else { return }
        var pages = collections["coloring_pages"] ?? []
        pages.removeAll {
          $0["book"] as? String == bookID
            && ($0["page_number"] as? Int ?? 0) > totalPages
            && ($0["status"] as? String == "not_started")
            && ($0["photos"] as? [String] ?? []).isEmpty
            && ($0["revealed_subject"] as? String ?? "").isEmpty
            && ($0["started_at"] as? String ?? "").isEmpty
            && ($0["completed_at"] as? String ?? "").isEmpty
        }
        let existing = Set(
          pages.compactMap { page in
            page["book"] as? String == bookID ? page["page_number"] as? Int : nil
          }
        )
        guard totalPages > 0 else {
          collections["coloring_pages"] = pages
          return
        }
        for pageNumber in 1...totalPages where !existing.contains(pageNumber) {
          sequence += 1
          pages.append([
            "id": "fixture-page-\(sequence)", "book": bookID, "page_number": pageNumber,
            "status": "not_started", "photos": [], "created": "2026-09-19 15:00:00",
            "updated": "2026-09-19 15:00:00", "expand": ["book": book],
          ])
        }
        collections["coloring_pages"] = pages
      }
    }

    private func respond(object: [String: Any], status: Int = 200) {
      respond(data: try! JSONSerialization.data(withJSONObject: object), status: status)
    }

    private func respond(data: Data, type: String = "application/json", status: Int = 200) {
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil,
        headerFields: ["Content-Type": type]
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    }

    private static var designDiamonds: [[String: Any]] {
      let artists = ["Example Artist One", "Example Artist Two", "Example Artist Three", "Fictional Artist"]
      let images = [
        "design-summer-garden-blooms.jpg", "design-misty-mount-rainier.jpg",
        "design-monarch-in-the-garden.jpg", "design-golden-eyed-tabby.jpg",
      ]
      let featured = zip(
        ["Summer Garden Blooms", "Misty Mount Rainier", "Monarch in the Garden", "Golden-Eyed Tabby"],
        ["progress", "stash", "progress", "completed"]
      ).enumerated().map { index, pair in
        var project: [String: Any] = [
          "id": "design-project-\(index)", "user": "preview-user", "title": pair.0,
          "status": pair.1, "kit_category": "full", "drill_shape": "square",
          "company": "design-company", "artist": "design-artist-\(index)",
          "width": 40, "height": 50,
          "image": images[index],
          "created": "2026-09-01", "updated": "2026-09-19 12:0\(9 - index * 2):00",
          "expand": [
            "company": ["id": "design-company", "name": "Example Atelier"],
            "artist": ["id": "design-artist-\(index)", "name": artists[index]],
          ],
        ]
        if pair.1 == "progress" {
          project["date_started"] = "2026-09-03"
        } else if pair.1 == "completed" {
          project["date_completed"] = "2026-09-17"
        }
        if index == 0 {
          project["general_notes"] =
            "<p>Bright summer blooms in every <strong>color</strong>.</p><p>Save the AB drills for the petals.</p>"
          project["drill_shape"] = "round"
          project["total_diamonds"] = 48_200
          project["color_count"] = 36
          project["date_purchased"] = "2026-07-02"
          project["date_received"] = "2026-07-11"
          project["date_started"] = "2026-08-14"
          project["source_url"] = "https://unsplash.com/photos/MRjuroFzfQw"
          var expand = project["expand"] as! [String: Any]
          expand["project_tags_via_project"] = [("Gardens", "tag-gardens"), ("Florals", "tag-florals")].map {
            ["id": "pt-\($0.1)", "expand": ["tag": ["id": $0.1, "name": $0.0]]]
          }
          project["expand"] = expand
        }
        if ProcessInfo.processInfo.arguments.contains("-fixture-long-library-text") {
          project["title"] = "A Garden of Wildflowers Beneath the Moon and Stars"
          var expand = project["expand"] as! [String: Any]
          expand["company"] = ["id": "design-company", "name": "The Example Diamond Painting Company"]
          expand["artist"] = ["id": "design-artist-\(index)", "name": "Alexandra Example and the Garden Illustration Studio"]
          project["expand"] = expand
        }
        return project
      }
      let extraKits = [
        ("Mirror Lake Reflections", "purchased", "design-mirror-lake-reflections.jpg"),
        ("San Diego Sunset", "wishlist", "design-san-diego-sunset.jpg"),
      ].enumerated().map { index, kit -> [String: Any] in
        [
          "id": "design-project-extra-\(index)", "user": "preview-user", "title": kit.0,
          "status": kit.1, "kit_category": "full", "drill_shape": "round",
          "width": 40, "height": 50, "image": kit.2,
          "created": "2026-08-01", "updated": "2026-08-01",
          "date_purchased": "2026-07-10", "date_received": "2026-07-20",
          "company": "example-company", "artist": "example-artist",
          "expand": [
            "company": ["id": "example-company", "name": "Example Kits"],
            "artist": ["id": "example-artist", "name": "Example Artist"],
          ],
        ]
      }
      return featured + extraKits
    }

    private static var designBooks: [[String: Any]] {
      [
        ("Smithsonian Libraries Coloring Pages, Volume 2", "in_progress", 11, "Smithsonian Libraries"),
        ("Exoplanet Travel Bureau Coloring Book", "in_stash", 6, "NASA/JPL-Caltech"),
        ("Our Very Own Star: The Sun", "in_stash", 9, "NASA Goddard Space Flight Center"),
        ("NASA's Field Guide to Black Holes Coloring Book", "in_progress", 3, "NASA"),
      ].enumerated().map { index, book in
        [
          "id": "design-book-\(index)", "user": "preview-user", "title": book.0,
          "status": book.1, "total_pages": book.2, "completed_pages": index == 0 ? 1 : 0,
          "completion_percentage": index == 0 ? 100.0 / Double(book.2) : 0,
          "cover_image": "design-book-\(index).jpg", "publisher": "design-publisher-\(index)",
          "created": "2026-09-01",
          "updated": "2026-09-19 10:00:00",
          "expand": ["publisher": ["id": "design-publisher-\(index)", "name": book.3]],
        ]
      }
    }

    private static var designPages: [[String: Any]] {
      let titles = ["Passionflowers", "Garden Lady", "Ornament Panels", "Poppy Maiden"]
      return (0..<11).map { index in
        var page: [String: Any] = [
          "id": "design-page-\(index)", "book": "design-book-0", "page_number": index + 1,
          "status": index == 0 ? "in_progress" : index == 1 ? "completed" : "not_started",
          "photos": ["design-page-\(index + 1).jpg"],
          "created": "2026-09-01", "updated": "2026-09-19 12:08:00",
          "expand": ["book": designBooks[0]],
        ]
        if titles.indices.contains(index) {
          page["revealed_subject"] = titles[index]
        }
        if index == 0 {
          page["started_at"] = "2026-09-18 11:00:00"
        } else if index == 1 {
          page["completed_at"] = "2026-09-17 11:00:00"
        }
        return page
      }
    }

    private static func designNoteDate(daysAgo: Int) -> String {
      let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
      return DetailDateOnly.string(from: date)
    }

    private static var designProgressNotes: [[String: Any]] {
      [
        [
          "id": "design-note-1", "project": "design-project-0",
          "content": "The flowers are starting to take shape.", "date": designNoteDate(daysAgo: 1),
          "image": "design-summer-garden-blooms.jpg", "created": "2026-09-18 16:00:00",
          "updated": "2026-09-18 16:00:00",
        ],
        [
          "id": "design-note-2", "project": "design-project-0",
          "content": "Finished the first color family.", "date": designNoteDate(daysAgo: 2),
          "created": "2026-09-15 16:00:00", "updated": "2026-09-15 16:00:00",
        ],
        [
          "id": "design-note-3", "project": "design-project-0",
          "content": "", "date": designNoteDate(daysAgo: 3), "image": "design-summer-garden-blooms.jpg",
          "created": "2026-09-08 16:00:00", "updated": "2026-09-08 16:00:00",
        ],
        [
          "id": "design-note-4", "project": "design-project-0",
          "content": "Started in the top corner.", "date": designNoteDate(daysAgo: 4),
          "image": "design-summer-garden-blooms.jpg",
          "created": "2026-08-14 16:00:00", "updated": "2026-08-14 16:00:00",
        ],
      ]
    }

    private static var designPageProgressNotes: [[String: Any]] {
      [
        [
          "id": "design-page-note-1", "user": "preview-user", "page": "design-page-0",
          "content": "The first **colors** are in place.", "date": designNoteDate(daysAgo: 0),
          "image": "design-page-1.jpg", "created": "2026-09-19 15:00:00",
          "updated": "2026-09-19 15:00:00",
        ],
        [
          "id": "design-page-note-2", "user": "preview-user", "page": "design-page-0",
          "content": "Started with the leaves and flowers.", "date": "2026-08-20",
          "created": "2026-08-20 15:00:00", "updated": "2026-08-20 15:00:00",
        ],
      ]
    }

    /// Serves the example account's openly licensed artwork, or a drawn stand-in for other files.
    private static func artwork(filename: String) -> Data {
      if let image = UIImage(named: (filename as NSString).deletingPathExtension),
        let data = image.jpegData(compressionQuality: 0.9)
      {
        return data
      }
      let seed = filename.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
      let hue = CGFloat(seed % 360) / 360
      let size = CGSize(width: 600, height: 750)
      let image = UIGraphicsImageRenderer(size: size).image { context in
        UIColor(hue: hue, saturation: 0.35, brightness: 0.85, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: size))
        UIColor(hue: (hue + 0.5).truncatingRemainder(dividingBy: 1), saturation: 0.45, brightness: 0.95, alpha: 1)
          .setFill()
        context.cgContext.fillEllipse(in: CGRect(x: 150, y: 225, width: 300, height: 300))
      }
      return image.jpegData(compressionQuality: 0.9) ?? Data()
    }
  }
#endif
