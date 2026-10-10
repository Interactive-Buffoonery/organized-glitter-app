import Foundation

struct ColoringPageMediumWrite: Codable, Equatable, Sendable {
  let mediums: [String]

  init(selection: Set<String>) {
    mediums = selection.sorted()
  }

  init(baseline: [String]) {
    mediums = baseline
  }
}

struct PageMediumAttempt: Codable, Equatable, Identifiable, Sendable {
  enum State: String, Codable, Sendable {
    case awaitingReceipt, conflict, missing, rejected, integrityFailure
  }

  let id: UUID
  let pageID: String
  let base: ColoringPageMediumWrite
  let patch: ColoringPageMediumWrite
  var state: State = .awaitingReceipt
  var current: ColoringPageRecord?

  init(pageID: String, baseline: [String], selection: Set<String>, id: UUID = UUID()) {
    self.id = id
    self.pageID = pageID
    base = ColoringPageMediumWrite(baseline: baseline)
    patch = ColoringPageMediumWrite(selection: selection)
  }
}

enum PageMediumSaveError: Error, Equatable {
  case integrityFailure
  case needsReview
  case recoveryRequired
}
