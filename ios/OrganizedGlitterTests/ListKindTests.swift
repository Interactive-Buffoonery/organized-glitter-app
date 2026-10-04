import Testing

@testable import OrganizedGlitter

struct ListKindTests {
  @Test(arguments: ListKind.allCases)
  func usageFilterMatchesRelation(kind: ListKind) {
    let fields: [ListKind: String] = [
      .company: "company", .artist: "artist", .diamondTag: "tag",
      .publisher: "publisher", .illustrator: "illustrator", .coloringTag: "tag",
      .medium: "mediums.id",
    ]
    let comparison = kind == .medium ? "?=" : "="
    #expect(kind.usageFilter(entryID: "entry") == "\(fields[kind]!) \(comparison) \"entry\"")
  }

  @Test func slugMatchesWebApp() {
    #expect(ListKind.slug(for: "  Big Florals! ") == "big-florals")
    #expect(ListKind.slug(for: "Café & Co.") == "caf-co")
  }

  @Test(arguments: [ListKind.diamondTag, .coloringTag])
  func tagNamesRequireSlugCharacters(kind: ListKind) {
    for name in ["✨", "!!!", " -- ", "é"] {
      #expect(kind.nameValidationMessage(name) == "Use at least one letter or number.")
    }
    for name in ["", "  ", "Café", "123", "Flowers ✨"] {
      #expect(kind.nameValidationMessage(name) == nil)
    }
  }

  @Test(arguments: [ListKind.company, .artist, .publisher, .illustrator, .medium])
  func otherListNamesDoNotRequireSlugs(kind: ListKind) {
    #expect(kind.nameValidationMessage("✨") == nil)
  }

  @Test func tagsAndMediumsCarryRequiredFields() {
    let tag = ListKind.coloringTag.createBody(name: "Mandalas", userID: "u1")
    #expect(tag["slug"] == "mandalas")
    #expect(ListKind.tagColors.contains(tag["color"] ?? ""))
    #expect(ListKind.medium.createBody(name: "Pens", userID: "u1")["type"] == "other")
    #expect(ListKind.company.createBody(name: "Acme", userID: "u1") == ["user": "u1", "name": "Acme"])
  }

  @Test func diamondAndColoringTagsStaySeparate() {
    #expect(ListKind.diamondTag.collection != ListKind.coloringTag.collection)
    #expect(ListKind.medium.usageFilter(entryID: "m1") == "mediums.id ?= \"m1\"")
  }
}
