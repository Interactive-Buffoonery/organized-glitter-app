import Foundation
import Testing

@testable import OrganizedGlitter

struct ManageListsTests {
  @Test func namesRejectEmptyAndCaseInsensitiveDuplicates() {
    let entries = [NamedRelationRecord(id: "one", name: "Florals")]
    #expect(ListEntryNames.validation(" \n", entries: entries) == "Enter a name.")
    #expect(ListEntryNames.validation(" FLORALS ", entries: entries) != nil)
    #expect(ListEntryNames.validation("Florals", entries: entries, excluding: "one") == nil)
    #expect(ListEntryNames.validation("Animals", entries: entries) == nil)
  }

  @Test func usageTitlesFollowParentRelations() throws {
    let record = try JSONDecoder().decode(
      ListUsageRecord.self,
      from: Data(#"{"title":"Direct title","page_number":3,"expand":{"project":{"title":"Kit"},"book":{"title":"Book"}}}"#.utf8))
    #expect(record.displayTitle(kind: .company) == "Direct title")
    #expect(record.displayTitle(kind: .diamondTag) == "Kit")
    #expect(record.displayTitle(kind: .coloringTag) == "Book")
    #expect(record.displayTitle(kind: .medium) == "Page 3 · Book")
    let missing = try JSONDecoder().decode(ListUsageRecord.self, from: Data("{}".utf8))
    #expect(missing.displayTitle(kind: .medium) == "Page ? · Unavailable book")
  }
}
