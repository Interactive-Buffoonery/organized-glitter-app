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

    #expect(TaxonomyOptions.fromDownloadedLibrary(
      items, kind: .publisher, userID: "feature-user") == [publisher])
    #expect(TaxonomyOptions.fromDownloadedLibrary(
      items, kind: .illustrator, userID: "feature-user") == [illustrator])
    #expect(TaxonomyOptions.fromDownloadedLibrary(
      items, kind: .company, userID: "feature-user").isEmpty)
  }

  @Test
  func conflictLabelsUseReadableFieldNames() {
    #expect(ConflictFieldName.label(for: "kit_category") == "Kit type")
    #expect(ConflictFieldName.label(for: "revealed_subject") == "Revealed subject")
    #expect(ConflictFieldName.label(for: "title") == "Title")
  }

  @Test
  func conflictRelationsUseAccountNamesWithoutExposingUnknownIDs() {
    let book = featureBook("book", title: "Garden").withExpand(
      ColoringBookExpand(
        publisher: NamedRelationRecord(id: "publisher-1", name: "Paper House"),
        illustrator: NamedRelationRecord(id: "illustrator-1", name: "Aster")))
    let sibling = featureBook("sibling", title: "Moonlight").withExpand(
      ColoringBookExpand(
        publisher: NamedRelationRecord(id: "publisher-2", name: "Moon Press"),
        illustrator: nil))
    let otherAccountBook = ColoringBookRecord(
      id: "other", user: "another-user", title: "Private", series: nil,
      status: "purchased", totalPages: 40, completedPages: nil,
      completionPercentage: nil, coverImage: nil, publisher: "other-publisher",
      illustrator: nil, created: "2026-09-01", updated: "2026-09-01",
      expand: ColoringBookExpand(
        publisher: NamedRelationRecord(id: "other-publisher", name: "Other Account"),
        illustrator: nil))
    let display = ConflictValueDisplay(
      item: .book(book), accountItems: [.book(sibling), .book(otherAccountBook)],
      userID: "feature-user")

    #expect(display.text(.string("publisher-1"), field: "publisher") == "Paper House")
    #expect(display.text(.string("publisher-2"), field: "publisher") == "Moon Press")
    #expect(display.text(.string("illustrator-1"), field: "illustrator") == "Aster")
    #expect(display.text(.string("other-publisher"), field: "publisher") == "Publisher unavailable")
    #expect(display.text(.string("deleted-publisher"), field: "publisher") == "Publisher unavailable")
    #expect(display.text(.null, field: "publisher") == "Not set")
  }
}
