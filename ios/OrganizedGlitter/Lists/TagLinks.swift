import Foundation

enum TagLinks {
  @MainActor
  static func sync(
    kind: ListKind, recordID: String, from old: Set<String>, to new: Set<String>,
    library: LibrarySession
  ) async throws {
    precondition(kind.isTag)
    guard old != new else { return }
    let parent: PocketBaseFilter.Field = kind == .diamondTag ? .project : .book
    let links: [Link] = try await library.client.allRecords(
      collection: kind.usageCollection,
      filter: PocketBaseFilter.equals(parent, recordID))
    let existingTags = Set(links.map(\.tag))
    var changed = false
    do {
      for tag in new.subtracting(old).subtracting(existingTags).sorted() {
        let _: Link = try await library.create(
          collection: kind.usageCollection,
          body: [parent.rawValue: recordID, "tag": tag])
        changed = true
      }
      for link in links where old.subtracting(new).contains(link.tag) {
        try await library.delete(collection: kind.usageCollection, id: link.id)
        changed = true
      }
    } catch {
      if changed { try? await library.refresh(force: true) }
      throw error
    }
    if changed { try? await library.refresh(force: true) }
  }

  private struct Link: Decodable, Sendable {
    let id: String
    let tag: String
  }
}
