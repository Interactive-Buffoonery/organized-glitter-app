import Foundation
import Testing
@testable import OrganizedGlitter

struct OfflineGuidanceTests {
  @Test
  func downloadedBookRelationsRemainSelectableWithoutNetwork() {
    let publisher = NamedRelationRecord(id: "publisher-1", name: "Paper House")
    let illustrator = NamedRelationRecord(id: "illustrator-1", name: "Aster")
    let book = ColoringBookRecord(
      id: "book-1", user: "feature-user", title: "Garden", series: nil,
      status: "purchased", totalPages: 40, completedPages: nil,
      completionPercentage: nil, coverImage: nil,
      publisher: publisher.id, illustrator: illustrator.id,
      created: "2026-09-01", updated: "2026-09-01",
      expand: ColoringBookExpand(publisher: publisher, illustrator: illustrator))
    let otherAccountBook = ColoringBookRecord(
      id: "book-2", user: "another-user", title: "Secret", series: nil,
      status: "purchased", totalPages: 40, completedPages: nil,
      completionPercentage: nil, coverImage: nil,
      publisher: "other", illustrator: nil,
      created: "2026-09-01", updated: "2026-09-01",
      expand: ColoringBookExpand(
        publisher: NamedRelationRecord(id: "other", name: "Other Account"),
        illustrator: nil))
    let items: [LibraryItem] = [.book(book), .book(book), .book(otherAccountBook)]

    #expect(TaxonomyOptions.fromDownloadedBooks(
      items, collection: "book_publishers", userID: "feature-user") == [publisher])
    #expect(TaxonomyOptions.fromDownloadedBooks(
      items, collection: "book_illustrators", userID: "feature-user") == [illustrator])
    #expect(TaxonomyOptions.fromDownloadedBooks(
      items, collection: "unsupported", userID: "feature-user").isEmpty)
  }

  @Test
  func conflictLabelsUseReadableFieldNames() {
    #expect(ConflictFieldName.label(for: "kit_category") == "Kit type")
    #expect(ConflictFieldName.label(for: "revealed_subject") == "Revealed subject")
    #expect(ConflictFieldName.label(for: "title") == "Title")
  }
}
