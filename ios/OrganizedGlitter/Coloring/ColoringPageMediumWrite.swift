import Foundation

struct ColoringPageMediumWrite: Encodable, Sendable {
  let mediums: [String]

  init(selection: Set<String>) {
    mediums = selection.sorted()
  }
}
