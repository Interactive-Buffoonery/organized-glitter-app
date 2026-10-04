import Testing

@testable import OrganizedGlitter

struct DiamondProjectEditorTests {
  @Test
  func requiresANonWhitespaceTitle() {
    var draft = DiamondProjectDraft()
    draft.title = "   "
    #expect(!draft.isValid)

    draft.title = "Moon Garden"
    #expect(draft.isValid)
  }

  @Test
  func newProjectDefaultsDrillShapeToRound() {
    let draft = DiamondProjectDraft()
    #expect(draft.drillShape == "round")
  }

  @Test
  func existingProjectWithEmptyDrillShapeShowsNotSet() {
    let project = DiamondProjectRecord(
      id: "project-1",
      title: "Wolf Lake",
      user: "user-1",
      company: nil,
      artist: nil,
      status: "progress",
      kitCategory: "full",
      drillShape: nil,
      generalNotes: nil,
      width: nil,
      height: nil,
      image: nil,
      dateStarted: nil,
      dateCompleted: nil,
      created: "2026-01-01",
      updated: "2026-01-02",
      expand: nil
    )

    let draft = DiamondProjectDraft(project: project)
    #expect(draft.drillShape == "")
  }

  @Test
  func draftMatchesSavedRecord() {
    let draft = DiamondProjectDraft(
      project: DiamondProjectRecord(
        id: "project-1",
        title: "Wolf Lake",
        user: "user-1",
        company: nil,
        artist: nil,
        status: "progress",
        kitCategory: "full",
        drillShape: "round",
        generalNotes: nil,
        width: nil,
        height: nil,
        image: nil,
        dateStarted: nil,
        dateCompleted: nil,
        created: "2026-01-01",
        updated: "2026-01-02",
        expand: nil
      )
    )

    let matching = DiamondProjectRecord(
      id: "project-1",
      title: "Wolf Lake",
      user: "user-1",
      company: nil,
      artist: nil,
      status: "progress",
      kitCategory: "full",
      drillShape: "round",
      generalNotes: nil,
      width: nil,
      height: nil,
      image: nil,
      dateStarted: nil,
      dateCompleted: nil,
      created: "2026-01-01",
      updated: "2026-01-02",
      expand: nil
    )
    #expect(draft.matchesSavedRecord(matching))

    var draftWithWhitespace = draft
    draftWithWhitespace.title = "  Wolf Lake  "
    #expect(draftWithWhitespace.matchesSavedRecord(matching))

    let mismatchedTitle = DiamondProjectRecord(
      id: "project-1",
      title: "Moon Garden",
      user: "user-1",
      company: nil,
      artist: nil,
      status: "progress",
      kitCategory: "full",
      drillShape: "round",
      generalNotes: nil,
      width: nil,
      height: nil,
      image: nil,
      dateStarted: nil,
      dateCompleted: nil,
      created: "2026-01-01",
      updated: "2026-01-02",
      expand: nil
    )
    #expect(!draft.matchesSavedRecord(mismatchedTitle))

    let nilDrillShape = DiamondProjectRecord(
      id: "project-1",
      title: "Wolf Lake",
      user: "user-1",
      company: nil,
      artist: nil,
      status: "progress",
      kitCategory: "full",
      drillShape: nil,
      generalNotes: nil,
      width: nil,
      height: nil,
      image: nil,
      dateStarted: nil,
      dateCompleted: nil,
      created: "2026-01-01",
      updated: "2026-01-02",
      expand: nil
    )
    var clearedDraft = draft
    clearedDraft.drillShape = ""
    #expect(clearedDraft.matchesSavedRecord(nilDrillShape))
    #expect(!draft.matchesSavedRecord(nilDrillShape))
  }

  @Test
  func validatesAndNormalizesSourceLinks() {
    #expect(DiamondProjectDraft.normalizedSourceURL("example.com/x") == "https://example.com/x")
    #expect(DiamondProjectDraft.normalizedSourceURL(" http://example.com/x ") == "http://example.com/x")
    #expect(DiamondProjectDraft.normalizedSourceURL("") == "")
    for invalid in ["https://", "ftp://example.com", "not a link", "javascript:alert(1)"] {
      #expect(DiamondProjectDraft.normalizedSourceURL(invalid) == nil)
    }
  }

  @Test
  func validatesMeasurementBoundsAndWholeCounts() {
    var draft = DiamondProjectDraft()
    draft.title = "Kit"
    for invalid in ["-1", "1001", "nan", "infinity", "abc"] {
      draft.width = invalid
      #expect(!draft.isValid)
    }
    draft.width = "40.5"
    draft.height = "1000"
    draft.totalDiamonds = "2000000"
    draft.colorCount = "1000"
    #expect(draft.isValid)
    draft.totalDiamonds = "1.5"
    #expect(!draft.isValid)
    draft.totalDiamonds = "2000001"
    #expect(!draft.isValid)
    draft.totalDiamonds = ""
    draft.colorCount = "1001"
    #expect(!draft.isValid)
    #expect(DiamondProjectDraft.numberText(0).isEmpty)
  }

  @Test
  func notesEscapeHTMLAndRoundTripParagraphs() {
    let text = "A & B <tag> \"quoted\"\nNext line\n\nSecond paragraph"
    let html = DiamondProjectDraft.notesHTML(text)
    #expect(html == "<p>A &amp; B &lt;tag&gt; &quot;quoted&quot;<br>Next line</p>\n<p>Second paragraph</p>")
    #expect(html.plainTextFromHTML == text)
    #expect(DiamondProjectDraft.notesHTML("") == "")
  }
}
