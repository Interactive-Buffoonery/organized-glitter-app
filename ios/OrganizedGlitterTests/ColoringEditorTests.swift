import Foundation
import Testing

@testable import OrganizedGlitter

struct ColoringEditorTests {
  private func encodedObject(_ write: some Encodable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(write)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
  }

  private func makeBook(
    id: String = "book-1",
    user: String = "user-1",
    title: String = "Enchanted Forest",
    series: String? = "Johanna Basford",
    status: String = "in_progress",
    totalPages: Int = 40,
    completedPages: Int? = 5,
    completionPercentage: Double? = 12.5,
    coverImage: String? = nil,
    publisher: String? = "publisher-1",
    illustrator: String? = "illustrator-1",
    created: String = "2026-01-01",
    updated: String = "2026-01-02",
    expand: ColoringBookExpand? = nil
  ) -> ColoringBookRecord {
    ColoringBookRecord(
      id: id,
      user: user,
      title: title,
      series: series,
      status: status,
      totalPages: totalPages,
      completedPages: completedPages,
      completionPercentage: completionPercentage,
      coverImage: coverImage,
      publisher: publisher,
      illustrator: illustrator,
      created: created,
      updated: updated,
      expand: expand
    )
  }

  private func makePage(
    id: String = "page-1",
    book: String = "book-1",
    pageNumber: Int = 3,
    status: String = "in_progress",
    photos: [String] = [],
    revealedSubject: String? = "Fox",
    completedAt: String? = nil,
    startedAt: String? = "2026-01-01",
    created: String = "2026-01-01",
    updated: String = "2026-01-02",
    expand: ColoringPageExpand? = nil
  ) -> ColoringPageRecord {
    ColoringPageRecord(
      id: id,
      book: book,
      pageNumber: pageNumber,
      status: status,
      photos: photos,
      revealedSubject: revealedSubject,
      completedAt: completedAt,
      startedAt: startedAt,
      created: created,
      updated: updated,
      expand: expand
    )
  }

  @Test
  func bookDraftRequiresTitleAndAtLeastOnePage() {
    var draft = ColoringBookDraft()
    draft.title = ""
    #expect(!draft.isValid)

    draft.title = "   "
    #expect(!draft.isValid)

    draft.title = "Enchanted Forest"
    draft.totalPages = 0
    #expect(!draft.isValid)

    draft.totalPages = 1
    #expect(draft.isValid)
  }

  @Test
  func newBookDraftUsesDefaults() {
    let draft = ColoringBookDraft()
    #expect(draft.status == "purchased")
    #expect(draft.totalPages == 1)
    #expect(draft.series == "")
    #expect(draft.publisher == "")
    #expect(draft.illustrator == "")
  }

  @Test
  func bookDraftMatchesSavedRecord() {
    let record = makeBook()
    let draft = ColoringBookDraft(book: record)
    #expect(draft.matchesSavedRecord(record))

    var draftWithWhitespace = draft
    draftWithWhitespace.title = "  Enchanted Forest  "
    draftWithWhitespace.series = "  Johanna Basford  "
    #expect(draftWithWhitespace.matchesSavedRecord(record))

    // nil series/publisher/illustrator on the record match "" in the draft.
    let bare = makeBook(series: nil, publisher: nil, illustrator: nil)
    var clearedDraft = draft
    clearedDraft.series = ""
    clearedDraft.publisher = ""
    clearedDraft.illustrator = ""
    #expect(clearedDraft.matchesSavedRecord(bare))

    // Server-computed progress fields and the cover image are ignored.
    let recomputed = makeBook(
      completedPages: 40,
      completionPercentage: 100,
      coverImage: "cover.png"
    )
    #expect(draft.matchesSavedRecord(recomputed))

    #expect(!draft.matchesSavedRecord(makeBook(title: "Secret Garden")))
    #expect(!draft.matchesSavedRecord(makeBook(status: "completed")))
    #expect(!draft.matchesSavedRecord(makeBook(totalPages: 41)))
    #expect(!draft.matchesSavedRecord(makeBook(series: "Other Series")))
    #expect(!draft.matchesSavedRecord(makeBook(publisher: "publisher-2")))
    #expect(!draft.matchesSavedRecord(makeBook(illustrator: "illustrator-2")))
  }

  @Test
  func pageDraftMatchesSavedRecord() {
    let record = makePage()
    var draft = ColoringPageDraft(page: record)
    #expect(draft.matchesSavedRecord(record))

    draft.revealedSubject = "  Fox  "
    #expect(draft.matchesSavedRecord(record))

    #expect(!draft.matchesSavedRecord(makePage(status: "completed")))
    #expect(!draft.matchesSavedRecord(makePage(revealedSubject: "Owl")))

    let noSubject = makePage(revealedSubject: nil)
    var clearedDraft = draft
    clearedDraft.revealedSubject = ""
    #expect(clearedDraft.matchesSavedRecord(noSubject))
    #expect(!draft.matchesSavedRecord(noSubject))
  }

  @Test
  func bookWriteCreateIncludesAllFields() throws {
    var draft = ColoringBookDraft()
    draft.title = "  Enchanted Forest  "
    draft.series = "  Johanna Basford  "
    draft.status = "wishlist"
    draft.totalPages = 40
    draft.publisher = "publisher-1"
    draft.illustrator = "illustrator-1"

    let write = ColoringBookWrite.make(
      userID: "user-1",
      baseline: ColoringBookDraft(),
      draft: draft,
      isCreate: true
    )
    let object = try encodedObject(write)

    #expect(object["user"] as? String == "user-1")
    #expect(object["title"] as? String == "Enchanted Forest")
    #expect(object["series"] as? String == "Johanna Basford")
    #expect(object["status"] as? String == "wishlist")
    #expect(object["total_pages"] as? Int == 40)
    #expect(object["publisher"] as? String == "publisher-1")
    #expect(object["illustrator"] as? String == "illustrator-1")
  }

  @Test
  func bookWriteUpdateIncludesOnlyChangedTitle() throws {
    let baseline = ColoringBookDraft(book: makeBook())
    var draft = baseline
    draft.title = "Secret Garden"

    let write = ColoringBookWrite.make(
      userID: "user-1",
      baseline: baseline,
      draft: draft,
      isCreate: false
    )
    let object = try encodedObject(write)

    #expect(object["title"] as? String == "Secret Garden")
    #expect(object["user"] == nil)
    #expect(object["series"] == nil)
    #expect(object["status"] == nil)
    #expect(object["total_pages"] == nil)
    #expect(object["publisher"] == nil)
    #expect(object["illustrator"] == nil)
  }

  @Test
  func bookWriteUpdateSendsEmptyStringToClearFields() throws {
    let baseline = ColoringBookDraft(book: makeBook())
    var draft = baseline
    draft.series = ""
    draft.publisher = ""
    draft.illustrator = "illustrator-2"

    let write = ColoringBookWrite.make(
      userID: "user-1",
      baseline: baseline,
      draft: draft,
      isCreate: false
    )
    let object = try encodedObject(write)

    // PocketBase leaves PATCH fields untouched when the key is missing, so
    // clearing must send the key with the field's unset value.
    #expect(object["series"] as? String == "")
    #expect(object["publisher"] as? String == "")
    #expect(object["illustrator"] as? String == "illustrator-2")
    #expect(object["user"] == nil)
    #expect(object["title"] == nil)
    #expect(object["status"] == nil)
    #expect(object["total_pages"] == nil)
  }

  @Test
  func pageWriteIncludesOnlyChangedFields() throws {
    let baseline = ColoringPageDraft(page: makePage())

    let unchanged = ColoringPageWrite.make(baseline: baseline, draft: baseline)
    let unchangedObject = try encodedObject(unchanged)
    #expect(unchangedObject["status"] == nil)
    #expect(unchangedObject["revealed_subject"] == nil)

    var clearedDraft = baseline
    clearedDraft.revealedSubject = "   "
    let cleared = try encodedObject(
      ColoringPageWrite.make(baseline: baseline, draft: clearedDraft)
    )
    #expect(cleared["revealed_subject"] as? String == "")
    #expect(cleared["status"] == nil)

    var statusDraft = baseline
    statusDraft.status = "completed"
    let statusObject = try encodedObject(
      ColoringPageWrite.make(baseline: baseline, draft: statusDraft)
    )
    #expect(statusObject["status"] as? String == "completed")
    #expect(statusObject["revealed_subject"] == nil)

    // A page write must never carry ownership or relation keys.
    for object in [unchangedObject, cleared, statusObject] {
      #expect(object["user"] == nil)
      #expect(object["book"] == nil)
    }
  }
}
