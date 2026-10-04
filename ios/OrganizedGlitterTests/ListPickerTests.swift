import Foundation
import Testing
@testable import OrganizedGlitter

struct ListPickerTests {
  @Test(arguments: ListKind.allCases)
  func downloadedOptionsAreScopedAndDeduplicated(kind: ListKind) {
    let company = NamedRelationRecord(id: "company", name: "Company")
    let artist = NamedRelationRecord(id: "artist", name: "Artist")
    let publisher = NamedRelationRecord(id: "publisher", name: "Publisher")
    let illustrator = NamedRelationRecord(id: "illustrator", name: "Illustrator")
    let medium = NamedRelationRecord(id: "medium", name: "Medium")
    let diamondTag = TagRecord(id: "diamond-tag", name: "Diamond tag")
    let coloringTag = TagRecord(id: "coloring-tag", name: "Coloring tag")
    let project = featureProject("project", title: "Project").withExpand(
      DiamondProjectExpand(
        company: company, artist: artist,
        projectTags: [ProjectTagRecord(id: "link", expand: .init(tag: diamondTag))]))
    let book = featureBook("book", title: "Book").withExpand(
      ColoringBookExpand(
        publisher: publisher, illustrator: illustrator,
        bookTags: [ColoringBookTagRecord(id: "link", expand: .init(tag: coloringTag))]))
    let page = featurePage("page", book: book.id, number: 1).withExpand(
      ColoringPageExpand(
        book: ColoringPageBook(id: book.id, title: book.title, user: book.user),
        mediums: [medium]))
    let items: [LibraryItem] = [.diamond(project), .book(book), .page(page)]
    let expected: NamedRelationRecord
    switch kind {
    case .company: expected = company
    case .artist: expected = artist
    case .publisher: expected = publisher
    case .illustrator: expected = illustrator
    case .medium: expected = medium
    case .diamondTag: expected = .init(id: diamondTag.id, name: diamondTag.name)
    case .coloringTag: expected = .init(id: coloringTag.id, name: coloringTag.name)
    }
    #expect(TaxonomyOptions.fromDownloadedLibrary(
      items + items, kind: kind, userID: "feature-user") == [expected])
    #expect(TaxonomyOptions.fromDownloadedLibrary(
      items, kind: kind, userID: "another-user").isEmpty)
  }

  @Test
  func downloadedOptionsSortByName() {
    let first = featureProject("first", title: "First").withExpand(
      DiamondProjectExpand(company: .init(id: "z", name: "Zinnia"), artist: nil))
    let second = featureProject("second", title: "Second").withExpand(
      DiamondProjectExpand(company: .init(id: "a", name: "Aster"), artist: nil))
    #expect(TaxonomyOptions.fromDownloadedLibrary(
      [.diamond(first), .diamond(second)], kind: .company, userID: "feature-user")
      .map(\.name) == ["Aster", "Zinnia"])
  }

  @MainActor
  @Test
  func tagSummaryUsesNamesOrCount() {
    let options = ["Aster", "Birch", "Clover", "Daisy"].map {
      NamedRelationRecord(id: $0, name: $0)
    }
    #expect(TagPicker.summary(selection: [], options: options) == "None")
    for count in 1...3 {
      let names = Array(options.prefix(count).map(\.name))
      #expect(TagPicker.summary(selection: Set(names), options: options)
        == names.formatted(.list(type: .and)))
    }
    #expect(TagPicker.summary(selection: Set(options.map(\.id)), options: options) == "4 tags")
    #expect(TagPicker.summary(selection: ["unavailable"], options: []) == "1 tags")
  }
}
