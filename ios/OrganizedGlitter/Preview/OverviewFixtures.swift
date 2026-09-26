#if DEBUG
  import Foundation
  import UIKit

  /// Isolated, fictional responses for Overview runtime review. Never contacts a server.
  final class OverviewFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let store = FixtureStore()

    static var scenario: String? {
      let arguments = ProcessInfo.processInfo.arguments
      guard let index = arguments.firstIndex(of: "-overview-fixture"),
        arguments.indices.contains(index + 1)
      else { return arguments.contains("-ui-testing-authenticated") ? "populated" : nil }
      return arguments[index + 1]
    }

    static func session() -> URLSession {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [OverviewFixtureProtocol.self]
      return URLSession(configuration: configuration)
    }

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
        let type = url.lastPathComponent.hasSuffix(".jpg") ? "image/jpeg" : "image/png"
        respond(data: Self.artwork(filename: url.lastPathComponent), type: type)
        return
      }
      if url.path.contains("/auth-with-password") {
        respond(object: [
          "token": "fictional-fixture-token",
          "record": ["id": "preview-user", "verified": true, "username": "Fictional crafter"],
        ])
        return
      }
      let scenario = Self.scenario ?? "populated"
      let collection = Self.collectionAndID(from: url)?.collection
      if scenario == "loading", Self.contentCollections.contains(collection ?? "") { return }
      if scenario == "error", Self.contentCollections.contains(collection ?? "") {
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

      func response(for request: URLRequest, scenario: String) -> FixtureResponse {
        lock.lock()
        defer { lock.unlock() }

        if self.scenario != scenario {
          reset(for: scenario)
        }
        guard let url = request.url,
          let target = OverviewFixtureProtocol.collectionAndID(from: url)
        else {
          return FixtureResponse(object: ["message": "Unknown fixture request"], status: 404)
        }

        switch request.httpMethod ?? "GET" {
        case "GET":
          if let id = target.id {
            return get(collection: target.collection, id: id)
          }
          return list(collection: target.collection, url: url)
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
        let hasContent = scenario != "empty"
        collections = [
          "users": [
            [
              "id": "preview-user", "verified": true, "username": "Fictional crafter",
              "name": "Fictional crafter", "timezone": "America/New_York",
              "theme_preference": "system", "created": "2026-09-01 10:00:00",
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
            ? (scenario == "design"
              ? OverviewFixtureProtocol.designDiamonds : OverviewFixtureProtocol.diamondItems) : [],
          "coloring_books": hasContent
            ? (scenario == "design"
              ? OverviewFixtureProtocol.designBooks : OverviewFixtureProtocol.bookItems) : [],
          "coloring_pages": hasContent
            ? (scenario == "design"
              ? OverviewFixtureProtocol.designPages : OverviewFixtureProtocol.pageItems) : [],
          "progress_notes": hasContent
            ? (scenario == "design"
              ? OverviewFixtureProtocol.designProgressNotes
              : OverviewFixtureProtocol.progressNoteItems) : [],
        ]
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
        case "progress_notes":
          record["content"] = record["content"] ?? ""
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
      zip(["Peony garden", "Blue hour", "Citrus grove", "Wildflowers"],
          ["progress", "stash", "progress", "completed"]).enumerated().map { index, pair in
        var project: [String: Any] = [
          "id": "design-project-\(index)", "user": "preview-user", "title": pair.0,
          "status": pair.1, "kit_category": "full", "drill_shape": "square",
          "company": "design-company", "artist": "design-artist",
          "width": 40, "height": 50,
          "image": index == 2 ? "design-citrus.png" : index == 1 ? "design-moon.png" : "design-peony.png",
          "created": "2026-09-01", "updated": "2026-09-19 12:0\(9 - index * 2):00",
          "expand": [
            "company": ["id": "design-company", "name": "Fictional Atelier"],
            "artist": ["id": "design-artist", "name": "Fictional Artist"],
          ],
        ]
        if pair.1 == "progress" {
          project["date_started"] = "2026-09-03"
        } else if pair.1 == "completed" {
          project["date_completed"] = "2026-09-17"
        }
        if index == 0 {
          project["general_notes"] = "Soft florals with a deep green background."
        }
        return project
      }
    }

    private static var designBooks: [[String: Any]] {
      ["Botanical days", "Small wonders", "The secret woodland", "Garden birds"].enumerated().map { index, title in
        [
          "id": "design-book-\(index)", "user": "preview-user", "title": title,
          "status": "in_progress", "total_pages": 8, "completed_pages": 1,
          "completion_percentage": 12.5, "cover_image": "design-book-\(index).jpg",
          "publisher": "design-publisher", "illustrator": "design-illustrator",
          "created": "2026-09-01",
          "updated": "2026-09-19 10:00:00",
          "expand": [
            "publisher": ["id": "design-publisher", "name": "Fictional Press"],
            "illustrator": ["id": "design-illustrator", "name": "Fictional Artist"],
          ],
        ]
      }
    }

    private static var designPages: [[String: Any]] {
      let titles = ["Moonlit garden", "Fern study", "Summer stems", "Magnolias"]
      return (0..<8).map { index in
        var page: [String: Any] = [
          "id": "design-page-\(index)", "book": "design-book-0", "page_number": index + 1,
          "status": index == 0 ? "in_progress" : index == 1 ? "completed" : "not_started",
          "photos": index < 4 ? [index == 0 ? "design-moon.png" : "design-book.png"] : [],
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

    private static var designProgressNotes: [[String: Any]] {
      [
        [
          "id": "design-note-1", "project": "design-project-0",
          "content": "The flowers are starting to take shape.", "date": "2026-09-18",
          "image": "design-peony.png", "created": "2026-09-18 16:00:00",
          "updated": "2026-09-18 16:00:00",
        ],
        [
          "id": "design-note-2", "project": "design-project-0",
          "content": "Finished the first color family.", "date": "2026-09-15",
          "created": "2026-09-15 16:00:00", "updated": "2026-09-15 16:00:00",
        ],
      ]
    }

    private static func artwork(filename: String) -> Data {
      if filename.hasPrefix("design-book-"), filename.hasSuffix(".jpg"),
        let index = Int(filename.dropFirst("design-book-".count).dropLast(4)),
        let atlas = UIImage(named: "FixtureBookCovers")?.cgImage
      {
        let width = atlas.width / 2
        let height = atlas.height / 2
        let crop = CGRect(
          x: index.isMultiple(of: 2) ? 0 : width,
          y: index < 2 ? 0 : height,
          width: width,
          height: height
        )
        if let artwork = atlas.cropping(to: crop), let data = UIImage(cgImage: artwork).jpegData(
          compressionQuality: 0.9
        ) {
          return data
        }
      }
      if filename.hasPrefix("design-"), let atlas = UIImage(named: "FixtureArtwork")?.cgImage {
        let right = filename.contains("citrus") || filename.contains("book")
        let bottom = filename.contains("moon") || filename.contains("book")
        let width = atlas.width / 2
        let height = atlas.height / 2
        let crop = CGRect(x: right ? width : 0, y: bottom ? height : 0, width: width, height: height)
        if let artwork = atlas.cropping(to: crop), let data = UIImage(cgImage: artwork).pngData() {
          return data
        }
      }
      return UIGraphicsImageRenderer(size: CGSize(width: 200, height: 260)).pngData { context in
        UIColor(red: 0.18, green: 0.23, blue: 0.34, alpha: 1).setFill()
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 260))
        UIColor(red: 0.93, green: 0.81, blue: 0.57, alpha: 1).setFill()
        context.cgContext.fillEllipse(in: CGRect(x: 120, y: 28, width: 45, height: 45))
        for index in 0..<6 {
          UIColor(red: 0.4, green: 0.65, blue: 0.54, alpha: 1).setFill()
          context.cgContext.fillEllipse(
            in: CGRect(x: 15 + index * 30, y: 115 + (index % 2) * 30, width: 25, height: 90)
          )
        }
      }
    }
  }
#endif
