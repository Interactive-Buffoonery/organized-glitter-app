import Foundation

/// A user-owned list that records pick entries from. Each kind is its own
/// PocketBase collection, so diamond-art tags and coloring tags never share entries.
enum ListKind: String, CaseIterable, Identifiable, Sendable {
  case company, artist, diamondTag
  case publisher, illustrator, coloringTag, medium

  var id: Self { self }

  static let diamond: [ListKind] = [.company, .artist, .diamondTag]
  static let coloring: [ListKind] = [.publisher, .illustrator, .coloringTag, .medium]

  var collection: String {
    switch self {
    case .company: "companies"
    case .artist: "artists"
    case .diamondTag: "tags"
    case .publisher: "book_publishers"
    case .illustrator: "book_illustrators"
    case .coloringTag: "coloring_tags"
    case .medium: "coloring_mediums"
    }
  }

  var title: String {
    switch self {
    case .company: "Companies"
    case .artist: "Artists"
    case .diamondTag: "Diamond Art Tags"
    case .publisher: "Publishers"
    case .illustrator: "Illustrators"
    case .coloringTag: "Coloring Tags"
    case .medium: "Mediums"
    }
  }

  var singular: String {
    switch self {
    case .company: "Company"
    case .artist: "Artist"
    case .diamondTag, .coloringTag: "Tag"
    case .publisher: "Publisher"
    case .illustrator: "Illustrator"
    case .medium: "Medium"
    }
  }

  var systemImage: String {
    switch self {
    case .company: "building.2"
    case .artist: "paintbrush.pointed"
    case .diamondTag, .coloringTag: "tag"
    case .publisher: "books.vertical"
    case .illustrator: "pencil.and.scribble"
    case .medium: "pencil.tip"
    }
  }

  /// The records that point at an entry. Mirrors the server's taxonomy
  /// deletion guard, which refuses to delete an entry that is still in use.
  var usageCollection: String {
    switch self {
    case .company, .artist: "projects"
    case .diamondTag: "project_tags"
    case .publisher, .illustrator: "coloring_books"
    case .coloringTag: "coloring_book_tags"
    case .medium: "coloring_pages"
    }
  }

  func usageFilter(entryID: String) -> String {
    switch self {
    case .company: PocketBaseFilter.equals(.company, entryID)
    case .artist: PocketBaseFilter.equals(.artist, entryID)
    case .diamondTag, .coloringTag: PocketBaseFilter.equals(.tag, entryID)
    case .publisher: PocketBaseFilter.equals(.publisher, entryID)
    case .illustrator: PocketBaseFilter.equals(.illustrator, entryID)
    case .medium: PocketBaseFilter.anyEquals(.mediumID, entryID)
    }
  }

  var isTag: Bool { self == .diamondTag || self == .coloringTag }

  /// Body for creating an entry. Tags need the slug and color the web app
  /// derives; mediums require a type, which starts as "other".
  func createBody(name: String, userID: String) -> [String: String] {
    var body = ["user": userID, "name": name]
    if isTag {
      body["slug"] = ListKind.slug(for: name)
      body["color"] = ListKind.tagColors.randomElement()
    }
    if self == .medium { body["type"] = "other" }
    return body
  }

  /// Body for renaming an entry. Tags keep their slug in step with the name.
  func renameBody(name: String) -> [String: String] {
    isTag ? ["name": name, "slug": ListKind.slug(for: name)] : ["name": name]
  }

  /// Matches the web app's `generateSlug`.
  static func slug(for name: String) -> String {
    name.lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacing(#/[^a-z0-9]+/#, with: "-")
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  }

  /// The web app's tag palette.
  static let tagColors = [
    "#3B82F6", "#EF4444", "#10B981", "#F59E0B", "#8B5CF6", "#EC4899",
    "#6B7280", "#14B8A6", "#F97316", "#84CC16", "#6366F1", "#F43F5E",
  ]
}

