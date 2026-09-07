import Foundation

struct NamedRelationRecord: Codable, Hashable, Sendable {
  let id: String
  let name: String
}

struct DiamondProjectExpand: Codable, Hashable, Sendable {
  let company: NamedRelationRecord?
  let artist: NamedRelationRecord?
}

struct DiamondProjectRecord: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let title: String
  let user: String
  let company: String?
  let artist: String?
  let status: String
  let kitCategory: String
  let drillShape: String?
  let generalNotes: String?
  let width: Double?
  let height: Double?
  let image: String?
  let dateStarted: String?
  let dateCompleted: String?
  let created: String
  let updated: String
  let expand: DiamondProjectExpand?

  enum CodingKeys: String, CodingKey {
    case id, title, user, company, artist, status, width, height, image, created, updated, expand
    case kitCategory = "kit_category"
    case drillShape = "drill_shape"
    case generalNotes = "general_notes"
    case dateStarted = "date_started"
    case dateCompleted = "date_completed"
  }

  func withExpand(_ expand: DiamondProjectExpand?) -> DiamondProjectRecord {
    DiamondProjectRecord(
      id: id, title: title, user: user, company: company, artist: artist,
      status: status, kitCategory: kitCategory, drillShape: drillShape,
      generalNotes: generalNotes, width: width, height: height, image: image,
      dateStarted: dateStarted, dateCompleted: dateCompleted, created: created,
      updated: updated, expand: expand)
  }
}

struct ColoringBookExpand: Codable, Hashable, Sendable {
  let publisher: NamedRelationRecord?
  let illustrator: NamedRelationRecord?
}

struct ColoringBookRecord: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let user: String
  let title: String
  let series: String?
  let status: String
  let totalPages: Int
  let completedPages: Int?
  let completionPercentage: Double?
  let coverImage: String?
  let publisher: String?
  let illustrator: String?
  let created: String
  let updated: String
  let expand: ColoringBookExpand?

  enum CodingKeys: String, CodingKey {
    case id, user, title, series, status, publisher, illustrator, created, updated, expand
    case totalPages = "total_pages"
    case completedPages = "completed_pages"
    case completionPercentage = "completion_percentage"
    case coverImage = "cover_image"
  }

  func withExpand(_ expand: ColoringBookExpand?) -> ColoringBookRecord {
    ColoringBookRecord(
      id: id, user: user, title: title, series: series, status: status,
      totalPages: totalPages, completedPages: completedPages,
      completionPercentage: completionPercentage, coverImage: coverImage,
      publisher: publisher, illustrator: illustrator, created: created,
      updated: updated, expand: expand)
  }
}

struct ColoringPageExpand: Codable, Hashable, Sendable {
  let book: ColoringBookRecord?
}

struct ColoringPageRecord: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let book: String
  let pageNumber: Int
  let status: String
  let photos: [String]
  let revealedSubject: String?
  let completedAt: String?
  let startedAt: String?
  let created: String
  let updated: String
  let expand: ColoringPageExpand?

  enum CodingKeys: String, CodingKey {
    case id, book, status, photos, created, updated, expand
    case pageNumber = "page_number"
    case revealedSubject = "revealed_subject"
    case completedAt = "completed_at"
    case startedAt = "started_at"
  }

  func withExpand(_ expand: ColoringPageExpand?) -> ColoringPageRecord {
    ColoringPageRecord(
      id: id, book: book, pageNumber: pageNumber, status: status, photos: photos,
      revealedSubject: revealedSubject, completedAt: completedAt,
      startedAt: startedAt, created: created, updated: updated, expand: expand)
  }
}

struct DiamondProgressNoteExpand: Codable, Hashable, Sendable {
  let project: DiamondProjectRecord?
}

struct DiamondProgressNoteRecord: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let project: String
  let content: String
  let date: String
  let image: String?
  let created: String
  let updated: String
  let expand: DiamondProgressNoteExpand?
}

struct ColoringProgressNoteExpand: Codable, Hashable, Sendable {
  let page: ColoringPageRecord?
}

struct ColoringProgressNoteRecord: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let user: String
  let page: String
  let content: String
  let date: String
  let image: String?
  let created: String
  let updated: String
  let expand: ColoringProgressNoteExpand?
}

enum ProgressNoteItem: Hashable, Identifiable, Sendable {
  case diamond(DiamondProgressNoteRecord)
  case coloring(ColoringProgressNoteRecord)

  var id: String {
    switch self {
    case .diamond(let note): "diamond-note:\(note.id)"
    case .coloring(let note): "coloring-note:\(note.id)"
    }
  }

  var recordID: String {
    switch self {
    case .diamond(let note): note.id
    case .coloring(let note): note.id
    }
  }

  var content: String {
    switch self {
    case .diamond(let note): note.content
    case .coloring(let note): note.content
    }
  }

  var date: String {
    switch self {
    case .diamond(let note): note.date
    case .coloring(let note): note.date
    }
  }

  var title: String {
    switch self {
    case .diamond(let note):
      return note.expand?.project?.title ?? "Diamond project"
    case .coloring(let note):
      let page = note.expand?.page
      return page.map { "Page \($0.pageNumber)" } ?? "Coloring page"
    }
  }

  var subtitle: String {
    switch self {
    case .diamond:
      "Diamond painting"
    case .coloring(let note):
      note.expand?.page?.expand?.book?.title ?? "Coloring"
    }
  }
}

enum LibraryItem: Hashable, Identifiable, Sendable {
  case diamond(DiamondProjectRecord)
  case book(ColoringBookRecord)
  case page(ColoringPageRecord)

  var id: String {
    switch self {
    case .diamond(let project):
      "diamond:\(project.id)"
    case .book(let book):
      "book:\(book.id)"
    case .page(let page):
      "page:\(page.id)"
    }
  }

  var title: String {
    switch self {
    case .diamond(let project):
      project.title
    case .book(let book):
      book.title
    case .page(let page):
      page.revealedSubject?.nonEmpty ?? "Page \(page.pageNumber)"
    }
  }

  var subtitle: String {
    switch self {
    case .diamond(let project):
      [project.expand?.company?.name, project.expand?.artist?.name]
        .compactMap { $0?.nonEmpty }
        .joined(separator: " · ")
    case .book(let book):
      book.series?.nonEmpty ?? "\(book.completedPages ?? 0) of \(book.totalPages) pages"
    case .page(let page):
      page.expand?.book?.title ?? "Coloring page"
    }
  }

  var status: String {
    switch self {
    case .diamond(let project):
      project.status
    case .book(let book):
      book.status
    case .page(let page):
      page.status
    }
  }

  var updated: String {
    switch self {
    case .diamond(let project):
      project.updated
    case .book(let book):
      book.updated
    case .page(let page):
      page.updated
    }
  }

  var artworkAccessibilityLabel: String {
    switch self {
    case .diamond: "Project photo"
    case .book: "Book cover"
    case .page: "Page photo"
    }
  }

  /// Publisher/company for library cards; pages keep the parent book title.
  var libraryCaption: String {
    switch self {
    case .diamond(let project):
      project.expand?.company?.name.nonEmpty
        ?? project.expand?.artist?.name.nonEmpty
        ?? ""
    case .book(let book):
      book.expand?.publisher?.name.nonEmpty
        ?? book.series?.nonEmpty
        ?? ""
    case .page(let page):
      page.expand?.book?.title ?? ""
    }
  }

  func artworkURL(using client: PocketBaseClient) -> URL? {
    let collection: String
    let recordID: String
    let filename: String?
    switch self {
    case .diamond(let project):
      collection = "projects"
      recordID = project.id
      filename = project.image?.nonEmpty
    case .book(let book):
      collection = "coloring_books"
      recordID = book.id
      filename = book.coverImage?.nonEmpty
    case .page(let page):
      collection = "coloring_pages"
      recordID = page.id
      filename = page.photos.first(where: { !$0.isEmpty })
    }
    return filename.map {
      client.fileURL(collection: collection, recordID: recordID, filename: $0)
    }
  }

  /// Save responses omit relation expands. Reuse the previously listed
  /// expand so a record that stays off page 1 still has credits and parent book.
  func retainingListingContext(from previous: LibraryItem?) -> LibraryItem {
    guard let previous, previous.id == id else {
      return self
    }
    switch (self, previous) {
    case (.diamond(let project), .diamond(let prior)) where project.expand == nil:
      return .diamond(project.withExpand(prior.expand))
    case (.book(let book), .book(let prior)) where book.expand == nil:
      return .book(book.withExpand(prior.expand))
    case (.page(let page), .page(let prior)) where page.expand == nil:
      return .page(page.withExpand(prior.expand))
    default:
      return self
    }
  }
}

extension String {
  var nonEmpty: String? {
    isEmpty ? nil : self
  }

  var organizedGlitterLabel: String {
    switch self {
    case "in_stash": "In stash"
    case "in_progress", "progress": "In progress"
    case "on_hold", "onhold": "On hold"
    case "not_started": "Not started"
    case "palette_chosen": "Palette chosen"
    case "kitted": "Kitted up"
    default:
      replacingOccurrences(of: "_", with: " ").capitalized
    }
  }
}
