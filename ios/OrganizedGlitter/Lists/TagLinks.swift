import Foundation

/// Tag links are join records, so changes are online-only. The session
/// refreshes the library after each write.
enum TagLinks {
  @MainActor
  static func sync(
    kind: ListKind, recordID: String, from old: Set<String>, to new: Set<String>,
    library: LibrarySession
  ) async throws {
    precondition(kind.isTag)
    let parent: PocketBaseFilter.Field = kind == .diamondTag ? .project : .book
    let links: [Link] = try await library.client.allRecords(
      collection: kind.usageCollection,
      filter: PocketBaseFilter.equals(parent, recordID))
    let existingTags = Set(links.map(\.tag))
    for tag in new.subtracting(existingTags).sorted() {
      let _: Link = try await library.create(
        collection: kind.usageCollection, body: [parent.rawValue: recordID, "tag": tag])
    }
    for link in links where old.subtracting(new).contains(link.tag) {
      try await library.delete(collection: kind.usageCollection, id: link.id)
    }
  }

  private struct Link: Decodable, Sendable {
    let id: String
    let tag: String
  }
}
