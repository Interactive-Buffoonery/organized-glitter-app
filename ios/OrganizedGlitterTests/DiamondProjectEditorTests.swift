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
}
