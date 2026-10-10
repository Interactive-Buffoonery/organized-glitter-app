import Foundation
import Testing
@testable import OrganizedGlitter

struct RandomizerWheelGeometryTests {
  @Test(arguments: [1, 2, 3, 7, 48, 1000])
  func everyWinnerLandsAtPointerAcrossAccumulatedRotations(count: Int) throws {
    for start in [-450.0, 0, 123.5, 7534] {
      for index in 0..<count {
        let rotation = try #require(RandomizerWheelGeometry.targetRotation(
          from: start, winnerIndex: index, count: count))
        #expect(rotation >= start + 1800)
        #expect(RandomizerWheelGeometry.indexUnderPointer(rotation: rotation, count: count) == index)
        let segmentCenter = (Double(index) + 0.5) * 360 / Double(count)
        #expect(abs(RandomizerWheelGeometry.normalized(segmentCenter + rotation) - 270) < 0.000001)
      }
    }
  }

  @Test func rejectsEmptyAndInvalidGeometry() {
    #expect(RandomizerWheelGeometry.indexUnderPointer(rotation: 0, count: 0) == nil)
    #expect(RandomizerWheelGeometry.indexUnderPointer(rotation: .infinity, count: 2) == nil)
    #expect(RandomizerWheelGeometry.targetRotation(from: 0, winnerIndex: 2, count: 2) == nil)
    #expect(RandomizerWheelGeometry.targetRotation(from: .nan, winnerIndex: 0, count: 2) == nil)
  }

  @Test func selectedItemsUseTypedIDsAndReconcileLikeWeb() {
    let first = RandomizerCandidate(item: .diamond(featureProject("same", title: "Same")), bookTitle: nil)
    let second = RandomizerCandidate(item: .diamond(featureProject("other", title: "Same")), bookTitle: nil)
    let foreignKey = LocalRecordKey(kind: .book, id: "same")
    var selection = RandomizerItemSelection()
    selection.toggle(foreignKey, candidates: [first, second])
    #expect(selection.ids == nil)
    selection.toggle(first.id, candidates: [first, second])
    #expect(selection.ids == [second.id])
    selection.reconcile(candidates: [first])
    #expect(selection.ids == nil)
    selection.selectNone()
    selection.reconcile(candidates: [first, second])
    #expect(selection.ids == [])
    selection.toggle(first.id, candidates: [first, second])
    #expect(selection.ids == [first.id])
    selection.reconcile(candidates: [first])
    #expect(selection.ids == [first.id])
    selection.selectAll()
    #expect(selection.ids == nil)
  }

  @Test func explicitSelectionWritesAreIdempotent() {
    let first = RandomizerCandidate(item: .diamond(featureProject("first", title: "First")), bookTitle: nil)
    let second = RandomizerCandidate(item: .diamond(featureProject("second", title: "Second")), bookTitle: nil)
    var selection = RandomizerItemSelection()
    selection.selectNone()
    selection.setSelected(first.id, selected: true, candidates: [first, second])
    selection.setSelected(first.id, selected: true, candidates: [first, second])
    #expect(selection.ids == [first.id])
    selection.setSelected(first.id, selected: false, candidates: [first, second])
    selection.setSelected(first.id, selected: false, candidates: [first, second])
    #expect(selection.ids == [])
  }

  @Test func feedbackThrottlesAndStopsOnCancellationOrLanding() throws {
    let end = try #require(RandomizerWheelGeometry.targetRotation(from: 0, winnerIndex: 4, count: 8))
    let spin = RandomizerWheelSpin(selectionID: UUID(), startRotation: 0,
      endRotation: end, winnerIndex: 4, count: 8)
    var feedback = RandomizerSpinFeedback(spin: spin)
    let early = feedback.tick(at: 0.09)
    let first = feedback.tick(at: 0.11)
    let throttled = feedback.tick(at: 0.12)
    let landed = feedback.tick(at: 3)
    feedback.cancel()
    let cancelled = feedback.tick(at: 0.5)
    #expect(!early)
    #expect(first)
    #expect(!throttled)
    #expect(!landed)
    #expect(!cancelled)
    #expect(abs(RandomizerSpinFeedback.easeOut(0)) < 0.000001)
    #expect(abs(RandomizerSpinFeedback.easeOut(1) - 1) < 0.000001)
    #expect(RandomizerSpinFeedback.easeOut(0.5) > 0.5)
    #expect(RandomizerWheelGeometry.indexUnderPointer(rotation: end, count: 8) == 4)
  }

}
