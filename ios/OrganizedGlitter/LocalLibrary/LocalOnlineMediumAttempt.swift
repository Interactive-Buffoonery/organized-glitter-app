import Foundation
import SwiftData

@Model
final class LocalOnlineMediumAttempt {
  @Attribute(.unique) var key: String
  var scope: String
  var pageID: String
  var attemptData: Data

  init(scope: LocalAccountScope, attempt: PageMediumAttempt, data: Data) {
    key = "\(scope.storageKey)|\(attempt.pageID)"
    self.scope = scope.storageKey
    pageID = attempt.pageID
    attemptData = data
  }
}
