import Foundation
import Testing

@testable import OrganizedGlitter

struct DiamondProjectWriteTests {
  private func encodedObject(_ write: DiamondProjectWrite) throws -> [String: Any] {
    let data = try JSONEncoder().encode(write)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
  }

  private var baseline: DiamondProjectDraft {
    DiamondProjectDraft(
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
  }

  @Test
  func updateWriteIncludesOnlyChangedFields() throws {
    var draft = baseline
    draft.title = "Moon Garden"

    let write = DiamondProjectWrite.make(
      userID: "user-1",
      baseline: baseline,
      draft: draft,
      isCreate: false
    )
    let object = try encodedObject(write)

    #expect(object["title"] as? String == "Moon Garden")
    #expect(object["status"] == nil)
    #expect(object["kit_category"] == nil)
    #expect(object["drill_shape"] == nil)
    #expect(object["user"] == nil)
  }

  @Test
  func updateWriteOmitsUnchangedDrillShape() throws {
    var draft = baseline
    draft.status = "completed"

    let write = DiamondProjectWrite.make(
      userID: "user-1",
      baseline: baseline,
      draft: draft,
      isCreate: false
    )
    let object = try encodedObject(write)

    #expect(object["status"] as? String == "completed")
    #expect(object["drill_shape"] == nil)
  }

  @Test
  func sendsEmptyDrillShapeSoUpdatesCanClearIt() throws {
    var draft = baseline
    draft.drillShape = ""

    let write = DiamondProjectWrite.make(
      userID: "user-1",
      baseline: baseline,
      draft: draft,
      isCreate: false
    )
    let object = try encodedObject(write)

    // PocketBase leaves PATCH fields untouched when the key is missing, so
    // the key must be present with the select field's unset value.
    #expect(object["drill_shape"] as? String == "")
    #expect(object["title"] == nil)
    #expect(object["status"] == nil)
    #expect(object["kit_category"] == nil)
  }

  @Test
  func omitsUserOnUpdate() throws {
    let write = DiamondProjectWrite.make(
      userID: "user-1",
      baseline: baseline,
      draft: baseline,
      isCreate: false
    )

    #expect(try encodedObject(write)["user"] == nil)
  }

  @Test
  func includesUserOnCreate() throws {
    var draft = DiamondProjectDraft()
    draft.title = "Wolf Lake"
    draft.status = "wishlist"
    draft.kitCategory = "mini"
    draft.drillShape = "square"

    let write = DiamondProjectWrite.make(
      userID: "user-id",
      baseline: DiamondProjectDraft(),
      draft: draft,
      isCreate: true
    )
    let object = try encodedObject(write)

    #expect(object["user"] as? String == "user-id")
    #expect(object["title"] as? String == "Wolf Lake")
    #expect(object["status"] as? String == "wishlist")
    #expect(object["kit_category"] as? String == "mini")
    #expect(object["drill_shape"] as? String == "square")
  }
}
