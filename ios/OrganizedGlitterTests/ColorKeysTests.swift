import Foundation
import os
import Testing
@testable import OrganizedGlitter

private func key(
  _ id: String, position: Int, symbol: String = "u:0031", code: String = "",
  colorName: String = "", swatch: String = "", created: String = "2026-10-01 10:00:00.000Z",
  updated: String = "2026-10-01 10:00:00.000Z", page: String = "page", user: String = "feature-user"
) -> ColorKeyRecord {
  ColorKeyRecord(id: id, user: user, page: page, position: position, symbol: symbol, code: code,
    colorName: colorName, swatch: swatch, tried: [], note: "", created: created, updated: updated)
}

@Suite("Color key logic")
struct ColorKeyLogicTests {
  @Test("decodes server records, defaulting optional fields")
  func decodesDefensively() throws {
    let json = #"{"id":"k1","user":"u","page":"p","symbol":"u:0031","created":"c","updated":"u"}"#
    let record = try JSONDecoder().decode(ColorKeyRecord.self, from: Data(json.utf8))
    #expect(record.position == 0)
    #expect(record.tried == [])
    #expect(record.code == "" && record.colorName == "" && record.swatch == "" && record.note == "")
    let full = ##"{"id":"k2","user":"u","page":"p","position":3,"symbol":"u:0061","code":"B000","color_name":"Black","swatch":"#112233","tried":["B0000"],"note":"n","created":"c","updated":"u"}"##
    let decoded = try JSONDecoder().decode(ColorKeyRecord.self, from: Data(full.utf8))
    #expect(decoded.position == 3 && decoded.colorName == "Black" && decoded.tried == ["B0000"])
  }

  @Test("updates send only the changed fields, never user or page")
  func patchBody() throws {
    let original = ColorKeyWrite(user: "u", page: "p", position: 2, symbol: "r:abc123def456ghi",
      code: "B000", tried: ["R1"])
    var changed = original
    changed.colorName = "Black"
    changed.tried = ["R1", "R2"]
    let body = try #require(JSONSerialization.jsonObject(
      with: JSONEncoder().encode(ColorKeyPatch(original: original, changed: changed))) as? [String: Any])
    #expect(Set(body.keys) == ["color_name", "tried"])
    #expect(body["tried"] as? [String] == ["R1", "R2"])
    let empty = try JSONEncoder().encode(ColorKeyPatch(original: original, changed: original))
    #expect(String(decoding: empty, as: UTF8.self) == "{}")
  }

  @Test("writes always include position, even zero, and the full record")
  func writeBody() throws {
    let write = ColorKeyWrite(user: "u", page: "p", position: 0, symbol: "u:0031")
    let body = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(write)) as? [String: Any])
    #expect(body["position"] as? Int == 0)
    #expect(body["tried"] as? [String] == [])
    #expect(Set(body.keys) == ["user", "page", "position", "symbol", "code", "color_name", "swatch",
      "tried", "note"])
  }

  @Test("sorts by position, then created")
  func sorting() {
    let keys = [
      key("c", position: 1, created: "2026-10-01 10:00:02.000Z"),
      key("a", position: 2),
      key("b", position: 1, created: "2026-10-01 10:00:01.000Z"),
      key("d", position: 0),
    ]
    #expect(ColorKeys.sorted(keys).map(\.id) == ["d", "b", "c", "a"])
  }

  @Test("copy text uses a request's description, on one line")
  func copyTextRequestDescription() {
    let keys = [
      key("a", position: 0, symbol: "r:abc123def456ghi", code: "P2"),
      key("b", position: 1, symbol: "r:zzz123def456ghi", code: "P3"),
    ]
    let request = SymbolRequestRecord(id: "abc123def456ghi", user: "feature-user",
      description: "Two w’s\nstacked", photo: "photo.jpg")
    let text = ColorKeys.copyText(keys, catalog: .bundled, requests: [request.symbol: request])
    #expect(text == "Two w’s stacked P2\nSent symbol P3")
  }

  @Test("a symbol request needs a photo, a book and page, and an email")
  func requestValidation() {
    let photo = ProcessedDetailPhoto(data: Data([1]), fileName: "symbol.jpg", contentType: "image/jpeg")
    var draft = SymbolRequestDraft(bookLabel: " ", email: "me@example.com")
    #expect(draft.validationMessage != nil)
    draft.photo = photo
    #expect(draft.validationMessage != nil)
    draft.bookLabel = "Mystery Book · Page 3"
    #expect(draft.validationMessage == nil)
    draft.email = "not an email"
    #expect(draft.validationMessage != nil)
    draft.email = "me@example.com"
    draft.description = String(repeating: "a", count: 501)
    #expect(draft.validationMessage != nil)
  }

  @Test("copy text is one symbol and code per line, in position order, without selectors")
  func copyText() {
    let keys = [
      key("b", position: 1, symbol: "u:2665", code: "R29"),
      key("a", position: 0, symbol: "u:0031", code: "B000"),
      key("c", position: 2, symbol: "u:0061"),
      key("d", position: 3, symbol: "c:linked-circles", code: "W1"),
      key("e", position: 4, symbol: "r:abc123def456ghi", code: "P2"),
    ]
    let text = ColorKeys.copyText(keys, catalog: .bundled)
    #expect(text == "1 B000\n♥ R29\na\nLinked circles W1\nSent symbol P2")
    #expect(!text.unicodeScalars.contains { $0.value == 0xFE0E || $0.value == 0xFE0F })
  }

  @Test("code suggestions use the latest name and swatch for each matching code")
  func suggestions() {
    let history = [
      key("new", position: 0, code: "B000", colorName: "Pale porcelain", swatch: "#FFEEDD",
        updated: "2026-10-02 10:00:00.000Z"),
      key("old", position: 1, code: "b000", colorName: "Old name", swatch: "#000000",
        updated: "2026-10-01 10:00:00.000Z"),
      key("other", position: 2, code: "R29", colorName: "Red"),
      key("blank", position: 3, code: ""),
    ]
    let matches = ColorKeys.suggestions(for: "b0", history: history)
    #expect(matches == [ColorKeySuggestion(code: "B000", colorName: "Pale porcelain", swatch: "#FFEEDD")])
    #expect(ColorKeys.suggestions(for: " ", history: history).isEmpty)
    #expect(ColorKeys.suggestions(for: "b000", history: history).map(\.code) == ["B000"])
  }

  @Test("recent symbols are unique, valid, used with a code and most recent first")
  func recents() {
    let history = [
      key("1", position: 0, symbol: "u:0061", code: "A", updated: "2026-10-03 10:00:00.000Z"),
      key("2", position: 1, symbol: "u:0031", code: "B", updated: "2026-10-02 10:00:00.000Z"),
      key("3", position: 2, symbol: "u:0061", code: "C", updated: "2026-10-01 10:00:00.000Z"),
      key("4", position: 3, symbol: "bogus", code: "D", updated: "2026-10-04 10:00:00.000Z"),
      key("5", position: 4, symbol: "u:0062", updated: "2026-10-05 10:00:00.000Z"),
    ]
    #expect(ColorKeys.recentSymbols(history) == ["u:0061", "u:0031"])
  }

  @Test("setup writes enabled defaults then extras, in order, from position zero")
  func setupWrites() {
    let writes = ColorKeys.setupWrites(
      symbols: ["u:0031", "u:0061", "c:linked-circles"], user: "u", page: "p")
    #expect(writes.map(\.position) == [0, 1, 2])
    #expect(writes.map(\.symbol) == ["u:0031", "u:0061", "c:linked-circles"])
    #expect(writes.allSatisfy { $0.user == "u" && $0.page == "p" && $0.code.isEmpty })
  }

  @Test("reordering rewrites positions 0 to n-1 only for rows that moved")
  func reorderWrites() {
    let ordered = [key("c", position: 2), key("b", position: 1), key("a", position: 0), key("d", position: 5)]
    let writes = ColorKeys.reorderWrites(ordered)
    #expect(writes.map(\.original.id) == ["c", "a", "d"])
    #expect(writes.map(\.write.position) == [0, 2, 3])
  }

  @Test("next position follows the highest position")
  func nextPosition() {
    #expect(ColorKeys.nextPosition(after: []) == 0)
    #expect(ColorKeys.nextPosition(after: [key("a", position: 4), key("b", position: 1)]) == 5)
  }

  @Test("swatches are stored as #RRGGBB")
  func swatches() {
    #expect(ColorKeys.swatchHex(red: 1, green: 0.5, blue: 0) == "#FF8000")
    #expect(ColorKeys.swatchHex(red: 1.2, green: -0.1, blue: 0.2) == "#FF0033")
    #expect(ColorKeys.swatchComponents("#FF8000").map { [$0.red, $0.green, $0.blue] }
      == [1, 128.0 / 255, 0])
    #expect(ColorKeys.swatchComponents("#ff8000").map { [$0.red, $0.green, $0.blue] }
      == [1, 128.0 / 255, 0])
    #expect(ColorKeys.swatchComponents("FF8000") == nil)
    #expect(ColorKeys.swatchComponents("") == nil)
  }

  @Test("validation follows the contract limits")
  func validation() {
    var write = ColorKeyWrite(user: "u", page: "p", position: 0, symbol: "u:0031")
    #expect(ColorKeys.validationMessage(write) == nil)
    write.code = String(repeating: "x", count: 101)
    #expect(ColorKeys.validationMessage(write) != nil)
    write.code = ""
    write.tried = Array(repeating: "x", count: 21)
    #expect(ColorKeys.validationMessage(write) != nil)
    write.tried = [String(repeating: "x", count: 101)]
    #expect(ColorKeys.validationMessage(write) != nil)
    write.tried = []
    write.note = String(repeating: "x", count: 2001)
    #expect(ColorKeys.validationMessage(write) != nil)
    write.note = ""
    write.symbol = "u:41"
    #expect(ColorKeys.validationMessage(write) != nil)
  }

  @Test("writes trim fields and drop empty tried entries")
  func normalized() {
    var write = ColorKeyWrite(user: "u", page: "p", position: 0, symbol: "u:0031")
    write.code = "  B000 "
    write.colorName = " Black\n"
    write.tried = [" R1 ", "", "  "]
    write.note = " keep inner  spaces "
    let normalized = write.normalized
    #expect(normalized.code == "B000" && normalized.colorName == "Black")
    #expect(normalized.tried == ["R1"])
    #expect(normalized.note == "keep inner  spaces")
  }
}

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ColorKeysSessionTests {
  nonisolated private static let saved = #"{"id":"key1234567890ab","user":"feature-user","page":"page","position":0,"symbol":"u:0031","code":"","color_name":"","swatch":"","tried":[],"note":"","created":"2026-10-01 10:00:00.000Z","updated":"2026-10-01 10:00:00.000Z"}"#

  @Test("loads only this user's keys for the page, sorted")
  func loadsKeys() async throws {
    let library = try await makeLibrary()
    ColorKeyProtocol.respond { request in
      let other = Self.saved.replacingOccurrences(of: "\"feature-user\"", with: "\"someone-else\"")
        .replacingOccurrences(of: "key1234567890ab", with: "keyother0000000")
      let later = Self.saved.replacingOccurrences(of: "\"position\":0", with: "\"position\":2")
        .replacingOccurrences(of: "key1234567890ab", with: "keylater0000000")
      return (200, #"{"page":1,"perPage":50,"totalPages":1,"totalItems":3,"items":[\#(later),\#(Self.saved),\#(other)]}"#)
    }
    let keys = try await library.colorKeys(pageID: "page")
    #expect(keys.map(\.id) == ["key1234567890ab", "keylater0000000"])
    let url = try #require(ColorKeyProtocol.requests.last?.url)
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(url.path == "/api/collections/coloring_page_color_keys/records")
    #expect(query.first { $0.name == "filter" }?.value == #"user = "feature-user" && page = "page""#)
    #expect(query.first { $0.name == "sort" }?.value == "position,created")
  }

  @Test("creates send the full record, and the server's stored symbol wins")
  func createUsesServerSymbol() async throws {
    let library = try await makeLibrary()
    ColorKeyProtocol.respond { _ in
      (200, Self.saved.replacingOccurrences(of: "u:0031", with: "u:03C8"))
    }
    let write = ColorKeyWrite(user: "feature-user", page: "page", position: 0, symbol: "r:abc123def456ghi")
    let saved = try await library.saveColorKey(write, original: nil)
    #expect(saved.symbol == "u:03C8")
    let request = try #require(ColorKeyProtocol.requests.last)
    #expect(request.method == "POST")
    let body = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    #expect(body["position"] as? Int == 0)
    #expect(body["symbol"] as? String == "r:abc123def456ghi")
    #expect(body["user"] as? String == "feature-user" && body["page"] as? String == "page")
  }

  @Test("updates patch the record by ID with only the changed fields")
  func updates() async throws {
    let library = try await makeLibrary()
    ColorKeyProtocol.respond { _ in (200, Self.saved) }
    let original = try JSONDecoder().decode(ColorKeyRecord.self, from: Data(Self.saved.utf8))
    var write = original.write
    write.code = "B000"
    _ = try await library.saveColorKey(write, original: original)
    let request = try #require(ColorKeyProtocol.requests.last)
    #expect(request.method == "PATCH")
    #expect(request.url.path == "/api/collections/coloring_page_color_keys/records/key1234567890ab")
    let body = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    #expect(body as? [String: String] == ["code": "B000"])
  }

  @Test("a forbidden key doesn't sign the user out, an expired session does")
  func forbiddenKeepsSession() async throws {
    let library = try await makeLibrary()
    nonisolated(unsafe) var status = 403
    ColorKeyProtocol.respond { _ in (status, #"{"message":"no"}"#) }
    var signOuts = 0
    library.onAuthenticationFailure = { signOuts += 1 }
    await #expect(throws: APIError.forbidden) { try await library.colorKeys(pageID: "page") }
    #expect(signOuts == 0)
    status = 401
    await #expect(throws: APIError.unauthenticated) { try await library.colorKeys(pageID: "page") }
    #expect(signOuts == 1)
  }

  @Test("history asks only for this user's keys with a code")
  func historyQuery() async throws {
    let library = try await makeLibrary()
    ColorKeyProtocol.respond { _ in
      (200, #"{"page":1,"perPage":200,"totalPages":1,"totalItems":1,"items":[\#(Self.saved)]}"#)
    }
    #expect(try await library.colorKeyHistory().isEmpty)
    let url = try #require(ColorKeyProtocol.requests.last?.url)
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(query.first { $0.name == "filter" }?.value == #"user = "feature-user" && code != """#)
  }

  @Test("the section hides when the server has no color keys collection yet")
  func missingCollection() async throws {
    let library = try await makeLibrary()
    ColorKeyProtocol.respond { _ in (404, #"{"message":"Missing collection context."}"#) }
    let model = ColorKeysModel(library: library, pageID: "page")
    await model.load()
    #expect(model.loadState == .unavailable)
  }

  @Test("rejects saved records that belong to another user or page")
  func rejectsForeignResponses() async throws {
    let library = try await makeLibrary()
    ColorKeyProtocol.respond { _ in
      (200, Self.saved.replacingOccurrences(of: "\"page\":\"page\"", with: "\"page\":\"elsewhere\""))
    }
    let write = ColorKeyWrite(user: "feature-user", page: "page", position: 0, symbol: "u:0031")
    await #expect(throws: APIError.decoding) { try await library.saveColorKey(write, original: nil) }
  }

  @Test("writes stay online: offline saves are not sent")
  func offlineSaves() async throws {
    let library = try await makeLibrary(online: false)
    let write = ColorKeyWrite(user: "feature-user", page: "page", position: 0, symbol: "u:0031")
    await #expect(throws: APIError.offline) { try await library.saveColorKey(write, original: nil) }
    #expect(ColorKeyProtocol.requests.isEmpty)
  }

  @Test("the model replaces rows with saved records and keeps them sorted")
  func modelSave() async throws {
    let library = try await makeLibrary()
    ColorKeyProtocol.respond { request in
      request.method == "GET"
        ? (200, #"{"page":1,"perPage":50,"totalPages":1,"totalItems":0,"items":[]}"#)
        : (200, Self.saved.replacingOccurrences(of: "u:0031", with: "u:03C8")
          .replacingOccurrences(of: #""code":"""#, with: #""code":"B000""#))
    }
    let model = ColorKeysModel(library: library, pageID: "page")
    await model.load()
    #expect(model.keys.isEmpty && model.loadState == .loaded)
    let saved = try await model.save(
      ColorKeyWrite(user: "feature-user", page: "page", position: 0, symbol: "r:abc123def456ghi"), id: nil).get()
    #expect(saved.symbol == "u:03C8")
    #expect(model.keys.map(\.symbol) == ["u:03C8"])
    #expect(model.recentSymbols.first == "u:03C8")

    var edit = saved.write
    edit.colorName = " Black "
    _ = try await model.save(edit, id: saved.id).get()
    let request = try #require(ColorKeyProtocol.requests.last)
    #expect(request.method == "PATCH")
    let body = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: String])
    #expect(body == ["color_name": "Black"])
  }

  @Test("setup reloads after an uncertain failure and skips symbols already saved on retry")
  func setupRetry() async throws {
    let library = try await makeLibrary()
    let server = ColorKeyServer()
    ColorKeyProtocol.respond { request in server.handle(request, template: Self.saved) }
    let model = ColorKeysModel(library: library, pageID: "page")
    await model.load()
    let symbols = ["u:0031", "u:0032", "u:0033"]
    // The second create is stored, but its response is lost.
    #expect(await model.setUp(symbols: symbols) != nil)
    #expect(model.keys.map(\.symbol) == ["u:0031", "u:0032"])
    #expect(await model.setUp(symbols: symbols) == nil)
    #expect(model.keys.map(\.symbol) == symbols)
    #expect(model.keys.map(\.position) == [0, 1, 2])
    #expect(server.posts == 3)
  }

  @Test("a 401 during a save lets sign-out finish", .timeLimit(.minutes(1)))
  func expiredSessionDuringSave() async throws {
    let library = try await makeLibrary()
    ColorKeyProtocol.respond { _ in (401, #"{"message":"expired"}"#) }
    var closed = false
    library.onAuthenticationFailure = {
      try? await library.close(removingData: false)
      closed = true
    }
    let write = ColorKeyWrite(user: "feature-user", page: "page", position: 0, symbol: "u:0031")
    await #expect(throws: APIError.unauthenticated) { try await library.saveColorKey(write, original: nil) }
    #expect(closed)
  }

  @Test("retrying a create whose response was lost adopts the stored key")
  func lostCreateResponse() async throws {
    let library = try await makeLibrary()
    let server = ColorKeyServer(failingPost: 1)
    ColorKeyProtocol.respond { request in server.handle(request, template: Self.saved) }
    let model = ColorKeysModel(library: library, pageID: "page")
    await model.load()
    let write = ColorKeyWrite(user: "feature-user", page: "page", position: 0, symbol: "u:0031")
    let saved = try await model.save(write, id: nil).get()
    #expect(model.keys.map(\.id) == [saved.id])
    #expect(server.posts == 1)
  }

  @Test("a failed update after a lost create response doesn't create the key again")
  func lostCreateThenFailedUpdate() async throws {
    let library = try await makeLibrary()
    let server = ColorKeyServer(failingPost: 1)
    // The double answers every non-POST with a list, so the follow-up update fails to decode.
    ColorKeyProtocol.respond { request in server.handle(request, template: Self.saved) }
    let model = ColorKeysModel(library: library, pageID: "page")
    await model.load()
    var write = ColorKeyWrite(user: "feature-user", page: "page", position: 0, symbol: "u:0031")
    write.code = "PU306"
    await #expect(throws: ColorKeysModel.Failure.self) { try await model.save(write, id: nil).get() }
    await #expect(throws: ColorKeysModel.Failure.self) { try await model.save(write, id: nil).get() }
    #expect(server.posts == 1)
    #expect(ColorKeyProtocol.requests.filter { $0.method == "PATCH" }.count == 2)
  }

  @Test("changing the symbol after a lost create response updates the stored key")
  func lostCreateThenChangedSymbol() async throws {
    let library = try await makeLibrary()
    let server = ColorKeyServer(failingPost: 1)
    ColorKeyProtocol.respond { request in server.handle(request, template: Self.saved) }
    let model = ColorKeysModel(library: library, pageID: "page")
    await model.load()
    var write = ColorKeyWrite(user: "feature-user", page: "page", position: 0, symbol: "u:0031")
    write.code = "PU306"
    await #expect(throws: ColorKeysModel.Failure.self) { try await model.save(write, id: nil).get() }
    write.symbol = "u:0032"
    await #expect(throws: ColorKeysModel.Failure.self) { try await model.save(write, id: nil).get() }
    #expect(server.posts == 1)
    let patch = try #require(ColorKeyProtocol.requests.last { $0.method == "PATCH" })
    let body = try #require(JSONSerialization.jsonObject(with: patch.body) as? [String: Any])
    #expect(body["symbol"] as? String == "u:0032")
  }

  @Test("no new create is sent until the page shows whether the last one landed")
  func unconfirmedCreateBlocksRetry() async throws {
    let library = try await makeLibrary()
    let server = ColorKeyServer(failingPost: 1)
    let readable = OSAllocatedUnfairLock(initialState: true)
    ColorKeyProtocol.respond { request in
      request.method == "GET" && !readable.withLock { $0 }
        ? (500, #"{"message":"busy"}"#) : server.handle(request, template: Self.saved)
    }
    let model = ColorKeysModel(library: library, pageID: "page")
    await model.load()
    readable.withLock { $0 = false }
    let write = ColorKeyWrite(user: "feature-user", page: "page", position: 0, symbol: "u:0031")
    await #expect(throws: ColorKeysModel.Failure.self) { try await model.save(write, id: nil).get() }
    #expect(await model.setUp(symbols: ["u:0031", "u:0032"]) != nil)
    #expect(server.posts == 1)
    readable.withLock { $0 = true }
    #expect(await model.setUp(symbols: ["u:0031", "u:0032"]) == nil)
    #expect(model.keys.map(\.symbol) == ["u:0031", "u:0032"])
    #expect(server.posts == 2)
  }

  @Test("a load that finishes after a save keeps the saved key")
  func staleLoadKeepsSave() async throws {
    let library = try await makeLibrary()
    ColorKeyProtocol.respond { request in
      request.method == "GET"
        ? (200, #"{"page":1,"perPage":50,"totalPages":1,"totalItems":0,"items":[]}"#) : (200, Self.saved)
    }
    let model = ColorKeysModel(library: library, pageID: "page")
    ColorKeyProtocol.holdResponses(true)
    let loading = Task { await model.load() }
    while ColorKeyProtocol.requests.isEmpty { await Task.yield() }
    ColorKeyProtocol.holdResponses(false)
    let write = ColorKeyWrite(user: "feature-user", page: "page", position: 0, symbol: "u:0031")
    let saved = try await model.save(write, id: nil).get()
    ColorKeyProtocol.releaseHeld()
    await loading.value
    #expect(model.keys.map(\.id) == [saved.id])
    #expect(model.loadState == .loaded)
  }

  nonisolated private static let request = #"{"id":"req123456789abc","user":"feature-user","page":"page","book_label":"Book · Page 3","description":"","email":"me@example.com","photo":"symbol_abc.jpg","status":"open","resolved_symbol":"","created":"2026-10-01 10:00:00.000Z","updated":"2026-10-01 10:00:00.000Z"}"#

  private static func requestDraft(description: String = "") -> SymbolRequestDraft {
    var draft = SymbolRequestDraft(bookLabel: "Book · Page 3", email: "me@example.com")
    draft.description = description
    draft.photo = ProcessedDetailPhoto(data: Data([0xFF, 0xD8]), fileName: "symbol.jpg", contentType: "image/jpeg")
    return draft
  }

  @Test("a symbol request sends the form and never the fields the server owns")
  func sendRequest() async throws {
    let library = try await makeLibrary()
    ColorKeyProtocol.respond { _ in (200, Self.request) }
    let model = ColorKeysModel(library: library, pageID: "page")
    let symbol = try await model.sendRequest(Self.requestDraft(description: "Two w’s stacked")).get()
    #expect(symbol == "r:req123456789abc")
    #expect(model.requests[symbol]?.photo == "symbol_abc.jpg")
    let sent = try #require(ColorKeyProtocol.requests.last)
    #expect(sent.method == "POST")
    #expect(sent.url.path.hasSuffix("/collections/coloring_symbol_requests/records"))
    let body = String(decoding: sent.body, as: UTF8.self)
    for field in ["user", "page", "book_label", "description", "email"] {
      #expect(body.contains("name=\"\(field)\""))
    }
    #expect(body.contains("name=\"photo\"; filename=\"symbol.jpg\""))
    #expect(!body.contains("name=\"status\""))
    #expect(!body.contains("name=\"resolved_symbol\""))
  }

  @Test("an empty description is left out of a symbol request")
  func sendRequestWithoutDescription() async throws {
    let library = try await makeLibrary()
    ColorKeyProtocol.respond { _ in (200, Self.request) }
    let model = ColorKeysModel(library: library, pageID: "page")
    _ = try await model.sendRequest(Self.requestDraft()).get()
    let body = String(decoding: try #require(ColorKeyProtocol.requests.last).body, as: UTF8.self)
    #expect(!body.contains("name=\"description\""))
  }

  @Test("a busy server asks the user to try a symbol request later")
  func busyRequest() async throws {
    let library = try await makeLibrary()
    ColorKeyProtocol.respond { _ in (429, #"{"message":"Too many requests."}"#) }
    let model = ColorKeysModel(library: library, pageID: "page")
    let result = await model.sendRequest(Self.requestDraft())
    #expect(throws: ColorKeysModel.Failure.self) { try result.get() }
    if case .failure(let failure) = result { #expect(failure.message.contains("Try again in a few minutes")) }
    #expect(model.requests.isEmpty)
  }

  @Test("loading a page fetches the requests its keys point to")
  func loadsRequests() async throws {
    let library = try await makeLibrary()
    let placeholder = Self.saved.replacingOccurrences(of: "u:0031", with: "r:req123456789abc")
    ColorKeyProtocol.respond { request in
      let item = request.url.path.contains("coloring_symbol_requests") ? Self.request : placeholder
      return (200, #"{"page":1,"perPage":50,"totalPages":1,"totalItems":1,"items":[\#(item)]}"#)
    }
    let model = ColorKeysModel(library: library, pageID: "page")
    await model.load()
    #expect(model.requests["r:req123456789abc"]?.photo == "symbol_abc.jpg")
    let lookup = try #require(ColorKeyProtocol.requests.last { $0.url.path.contains("coloring_symbol_requests") })
    let filter = URLComponents(url: lookup.url, resolvingAgainstBaseURL: false)?
      .queryItems?.first { $0.name == "filter" }?.value ?? ""
    #expect(filter.contains("user = \"feature-user\""))
    #expect(filter.contains("id = \"req123456789abc\""))
  }

  @Test("recently used requests from other pages load their photos")
  func loadsHistoryRequests() async throws {
    let library = try await makeLibrary()
    let placeholder = Self.saved.replacingOccurrences(of: "u:0031", with: "r:req123456789abc")
      .replacingOccurrences(of: #""code":"""#, with: #""code":"654""#)
    ColorKeyProtocol.respond { request in
      let query = request.url.query?.removingPercentEncoding ?? ""
      let item = request.url.path.contains("coloring_symbol_requests") ? Self.request
        : query.contains("page = ") ? "" : placeholder
      return (200, #"{"page":1,"perPage":50,"totalPages":1,"totalItems":1,"items":[\#(item)]}"#)
    }
    let model = ColorKeysModel(library: library, pageID: "page")
    await model.load()
    #expect(model.requests.isEmpty)
    await model.loadHistoryIfNeeded()
    #expect(model.requests["r:req123456789abc"]?.photo == "symbol_abc.jpg")
  }

  nonisolated private static func page(_ ids: [String]) -> String {
    let items = ids.enumerated().map { index, id in
      Self.saved.replacingOccurrences(of: "key1234567890ab", with: id)
        .replacingOccurrences(of: "\"position\":0", with: "\"position\":\(index)")
    }
    return #"{"page":1,"perPage":50,"totalPages":1,"totalItems":\#(ids.count),"items":[\#(items.joined(separator: ","))]}"#
  }

  nonisolated private static func echoPatch(_ request: ColorKeyProtocol.Request) -> (Int, String) {
    let id = request.url.lastPathComponent
    let body = (try? JSONSerialization.jsonObject(with: request.body) as? [String: Any]) ?? [:]
    return (200, Self.saved.replacingOccurrences(of: "key1234567890ab", with: id)
      .replacingOccurrences(of: "\"position\":0", with: "\"position\":\(body["position"] as? Int ?? 0)"))
  }

  @Test("reordering patches only the moved rows' positions and keeps the new order")
  func reorder() async throws {
    let library = try await makeLibrary()
    let ids = ["keya00000000000", "keyb00000000000", "keyc00000000000"]
    ColorKeyProtocol.respond { request in
      request.method == "GET" ? (200, Self.page(ids)) : Self.echoPatch(request)
    }
    let model = ColorKeysModel(library: library, pageID: "page")
    await model.load()
    let keys = model.keys
    await model.reorder([keys[0], keys[2], keys[1]])
    let patches = ColorKeyProtocol.requests.filter { $0.method == "PATCH" }
    #expect(patches.map(\.url.lastPathComponent) == ["keyc00000000000", "keyb00000000000"])
    let bodies = try patches.map { try #require(JSONSerialization.jsonObject(with: $0.body) as? [String: Int]) }
    #expect(bodies == [["position": 1], ["position": 2]])
    #expect(model.keys.map(\.id) == ["keya00000000000", "keyc00000000000", "keyb00000000000"])
    #expect(model.keys.map(\.position) == [0, 1, 2])
    #expect(model.reorderError == nil)

    let sent = ColorKeyProtocol.requests.count
    await model.reorder(model.keys)
    #expect(ColorKeyProtocol.requests.count == sent)
  }

  @Test("a reorder stops when confirming a pending create turns up a row the panel never showed")
  func reorderAfterRecoveredCreate() async throws {
    let library = try await makeLibrary()
    let ids = ["keya00000000000", "keyb00000000000"]
    let state = OSAllocatedUnfairLock(initialState: (readable: true, landed: false))
    ColorKeyProtocol.respond { request in
      let now = state.withLock { $0 }
      switch request.method {
      case "GET" where !now.readable: return (500, #"{"message":"busy"}"#)
      case "GET": return (200, Self.page(now.landed ? ids + ["keyn00000000000"] : ids))
      case "POST": return (500, #"{"message":"busy"}"#)
      default: return Self.echoPatch(request)
      }
    }
    let model = ColorKeysModel(library: library, pageID: "page")
    await model.load()
    let keys = model.keys
    state.withLock { $0.readable = false }
    let write = ColorKeyWrite(user: "feature-user", page: "page", position: 2, symbol: "u:0031")
    await #expect(throws: ColorKeysModel.Failure.self) { try await model.save(write, id: nil).get() }
    state.withLock { $0 = (readable: true, landed: true) }
    await model.reorder([keys[1], keys[0]])
    #expect(!ColorKeyProtocol.requests.contains { $0.method == "PATCH" })
    #expect(model.keys.map(\.id) == ids + ["keyn00000000000"])
    #expect(model.reorderError == "Couldn’t save the new order. Try again.")
  }

  @Test("a failed reorder restores the previous order, reloads and asks to try again")
  func reorderFailure() async throws {
    let library = try await makeLibrary()
    let ids = ["keya00000000000", "keyb00000000000", "keyc00000000000"]
    let patches = OSAllocatedUnfairLock(initialState: 0)
    ColorKeyProtocol.respond { request in
      guard request.method == "PATCH" else { return (200, Self.page(ids)) }
      let count = patches.withLock { $0 += 1; return $0 }
      return count == 2 ? (500, #"{"message":"busy"}"#) : Self.echoPatch(request)
    }
    let model = ColorKeysModel(library: library, pageID: "page")
    await model.load()
    let keys = model.keys
    let gets = ColorKeyProtocol.requests.filter { $0.method == "GET" }.count
    await model.reorder([keys[2], keys[1], keys[0]])
    #expect(patches.withLock { $0 } == 2)
    #expect(ColorKeyProtocol.requests.filter { $0.method == "GET" }.count == gets + 1)
    #expect(model.keys.map(\.id) == ids)
    #expect(model.reorderError == "Couldn’t save the new order. Try again.")
  }

  private func makeLibrary(online: Bool = true) async throws -> LibrarySession {
    ColorKeyProtocol.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ColorKeyProtocol.self]
    let keychain = KeychainSessionStore(service: "ColorKeysTests.\(UUID().uuidString)")
    let client = PocketBaseClient(baseURL: URL(string: "https://color-keys.example.invalid")!,
      sessionStore: keychain, urlSession: URLSession(configuration: configuration))
    _ = try await client.signIn(identity: "fixture", password: "fixture")
    try keychain.clear()
    ColorKeyProtocol.reset()
    return LibrarySession(client: client, userID: "feature-user",
      store: try LocalLibraryStore.inMemory(), connectionAvailable: online)
  }
}

/// Stores created keys; one create is stored but answered with a 500.
private final class ColorKeyServer: @unchecked Sendable {
  private let lock = NSLock()
  private let failingPost: Int
  private var stored: [String] = []
  private var postCount = 0
  var posts: Int { lock.withLock { postCount } }

  init(failingPost: Int = 2) { self.failingPost = failingPost }

  func handle(_ request: ColorKeyProtocol.Request, template: String) -> (Int, String) {
    lock.withLock {
      guard request.method == "POST" else {
        return (200, #"{"page":1,"perPage":50,"totalPages":1,"totalItems":\#(stored.count),"items":[\#(stored.joined(separator: ","))]}"#)
      }
      postCount += 1
      let posts = postCount
      let body = (try? JSONSerialization.jsonObject(with: request.body) as? [String: Any]) ?? [:]
      let record = template
        .replacingOccurrences(of: "key1234567890ab", with: "key\(posts)".padding(toLength: 15, withPad: "0", startingAt: 0))
        .replacingOccurrences(of: "u:0031", with: body["symbol"] as? String ?? "")
        .replacingOccurrences(of: "\"position\":0", with: "\"position\":\(body["position"] as? Int ?? 0)")
      stored.append(record)
      return posts == failingPost ? (500, #"{"message":"busy"}"#) : (200, record)
    }
  }
}

private final class ColorKeyProtocol: URLProtocol, @unchecked Sendable {
  struct Request: Sendable {
    let method: String
    let url: URL
    let body: Data
  }
  typealias Responder = @Sendable (Request) -> (Int, String)
  private static let lock = NSLock()
  nonisolated(unsafe) private static var recorded: [Request] = []
  nonisolated(unsafe) private static var responder: Responder?
  nonisolated(unsafe) private static var holding = false
  nonisolated(unsafe) private static var held: [(ColorKeyProtocol, Int, String)] = []

  static var requests: [Request] { lock.withLock { recorded } }
  static func reset() { lock.withLock { recorded = []; responder = nil; holding = false; held = [] } }
  static func respond(_ responder: @escaping Responder) { lock.withLock { self.responder = responder } }
  /// While on, responses wait until `releaseHeld()`.
  static func holdResponses(_ on: Bool) { lock.withLock { holding = on } }
  static func releaseHeld() {
    let responses = lock.withLock { defer { held = [] }; return held }
    for (instance, status, body) in responses { instance.respond(status, body) }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}
  override func startLoading() {
    let url = request.url!
    if url.path.hasSuffix("auth-with-password") {
      return respond(200, #"{"token":"fixture-token","record":{"id":"feature-user","verified":true}}"#)
    }
    let recorded = Request(method: request.httpMethod ?? "GET", url: url, body: Self.body(of: request))
    let (responder, holding) = Self.lock.withLock {
      Self.recorded.append(recorded)
      return (Self.responder, Self.holding)
    }
    let (status, body) = responder?(recorded) ?? (404, #"{"message":"missing"}"#)
    if holding { return Self.lock.withLock { Self.held.append((self, status, body)) } }
    respond(status, body)
  }

  private func respond(_ status: Int, _ body: String) {
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  private static func body(of request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while case let count = stream.read(&buffer, maxLength: buffer.count), count > 0 {
      data.append(buffer, count: count)
    }
    return data
  }
}
