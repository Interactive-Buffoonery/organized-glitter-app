import Foundation
import Testing
@testable import OrganizedGlitter

struct ColoringPageMediumTests {
  @Test
  func rawIDsPreserveUnexpandedSelectionsThroughEncoding() throws {
    var page = featurePage("page", book: "book", number: 1)
    page.mediumIDs = ["unavailable", "pencil"]
    let expanded = page.withExpand(ColoringPageExpand(
      book: nil, mediums: [.init(id: "pencil", name: "Pencils")]))
    let restored = try JSONDecoder().decode(
      ColoringPageRecord.self, from: JSONEncoder().encode(expanded))

    #expect(restored.mediumIDs == ["unavailable", "pencil"])
    #expect(restored.selectedMediumIDs == ["unavailable", "pencil"])
  }

  @Test
  func olderCachedPagesRecoverIDsFromDownloadedLabels() throws {
    let page = featurePage("page", book: "book", number: 1).withExpand(
      ColoringPageExpand(book: nil, mediums: [.init(id: "pencil", name: "Pencils")]))
    let restored = try JSONDecoder().decode(
      ColoringPageRecord.self, from: JSONEncoder().encode(page))

    #expect(restored.mediumIDs == nil)
    #expect(restored.selectedMediumIDs == ["pencil"])
    #expect(featurePage("empty", book: "book", number: 2).selectedMediumIDs.isEmpty)
  }

  @Test
  func explicitEmptyIDsOverrideStaleExpandedLabels() {
    var page = featurePage("page", book: "book", number: 1).withExpand(
      ColoringPageExpand(book: nil, mediums: [.init(id: "pencil", name: "Pencils")]))
    page.mediumIDs = []

    #expect(page.selectedMediumIDs.isEmpty)
  }

  @Test(arguments: [Set<String>(), ["pencil", "marker"]])
  func attachmentWritesOnlyTheMediumRelation(selection: Set<String>) throws {
    let data = try JSONEncoder().encode(ColoringPageMediumWrite(selection: selection))
    let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: [String]])

    #expect(Set(body.keys) == ["mediums"])
    #expect(body["mediums"] == selection.sorted())
  }

  @Test
  func storedMediumIDsStayAccountScopedAndOnlineOnly() async throws {
    let store = try LocalLibraryStore.inMemory()
    let scope = LocalAccountScope(
      backendURL: URL(string: "https://data.example.test")!, userID: "feature-user")
    let otherScope = LocalAccountScope(backendURL: scope.backendURL, userID: "another-user")
    var page = featurePage("page", book: "book", number: 1)
    page.mediumIDs = ["pencil", "unavailable"]
    try await store.ingestSnapshot(
      LocalFullSnapshot(
        version: 1, projects: [], coloringBooks: [featureBook("book", title: "Book")],
        coloringPages: [page], progressNotes: [], coloringPageProgressNotes: []),
      scope: scope)
    let entry = try #require(await store.entry(scope: scope, key: LibraryItem.page(page).localRecordKey))
    guard case .page(let stored) = entry.item else {
      Issue.record("Expected stored coloring page")
      return
    }
    #expect(stored.selectedMediumIDs == ["pencil", "unavailable"])
    #expect(try await store.entries(scope: otherScope).isEmpty)
    do {
      _ = try await store.queueEdit(
        scope: scope, key: entry.item.localRecordKey, patch: ["mediums": .null])
      Issue.record("Expected medium edits to remain online-only")
    } catch LocalLibraryError.unsupportedField {}
    #expect(try await store.pendingOperations(scope: scope).isEmpty)
  }
}
