import Foundation

enum SpinHistoryLoadState: Equatable {
  case idle, loading, loaded, failed
}

enum SpinHistorySaveState: Equatable {
  case saving, saved(String), notSent, rejected, unknown
}

extension SpinHistorySaveState {
  var failureAnnouncement: String? {
    switch self {
    case .notSent: RandomizerPageCopy.spinNotSent
    case .rejected: RandomizerPageCopy.spinRejected
    case .unknown: RandomizerPageCopy.spinUnknown
    case .saving, .saved: nil
    }
  }
}

struct SpinHistoryFailure: Identifiable, Equatable {
  let id: UUID
  let title: String
  let state: SpinHistorySaveState
}

struct SpinHistoryFailureAnnouncements {
  private var announced: Set<UUID> = []

  mutating func messages(for failures: [SpinHistoryFailure], isPageVisible: Bool) -> [String] {
    guard isPageVisible else { return [] }
    return failures.compactMap { failure in
      guard let message = failure.state.failureAnnouncement,
        announced.insert(failure.id).inserted else { return nil }
      return message
    }
  }
}

extension RandomizerMode {
  var spinWireValue: String {
    switch self {
    case .diamond: "diamond"
    case .book: "coloring-book"
    case .page: "coloring-page"
    }
  }

  var spinTargetType: String {
    switch self {
    case .diamond: "diamond_project"
    case .book: "coloring_book"
    case .page: "coloring_page"
    }
  }

  init?(spinWireValue: String) {
    switch spinWireValue {
    case "diamond": self = .diamond
    case "coloring-book": self = .book
    case "coloring-page": self = .page
    default: return nil
    }
  }

  init?(spinTargetType: String) {
    switch spinTargetType {
    case "diamond_project": self = .diamond
    case "coloring_book": self = .book
    case "coloring_page": self = .page
    default: return nil
    }
  }
}

struct SpinHistoryRecord: Decodable, Equatable, Identifiable, Sendable {
  let id: String
  let user: String
  let project: String?
  let projectTitle: String
  let spunAt: String
  let selectedProjects: [String]?
  let selectedCount: Int?
  let projectCompany: String?
  let projectArtist: String?
  private let metadata: ReadMetadata?

  var title: String { knownMetadata?.target?.title?.nonEmpty ?? projectTitle }
  var subtitle: String {
    knownMetadata?.target?.subtitle?.nonEmpty
      ?? [projectCompany, projectArtist].compactMap { $0?.nonEmpty }.joined(separator: " · ")
  }
  var mode: RandomizerMode {
    if let raw = knownMetadata?.mode, let value = RandomizerMode(spinWireValue: raw) { return value }
    if let raw = knownMetadata?.target?.targetType,
      let value = RandomizerMode(spinTargetType: raw) { return value }
    return .diamond
  }
  var optionCount: Int? {
    if let ids = knownMetadata?.selectedTargetIds, !ids.isEmpty { return ids.count }
    if let ids = selectedProjects, !ids.isEmpty { return ids.count }
    return selectedCount.flatMap { $0 > 0 ? $0 : nil }
  }
  var target: (mode: RandomizerMode, id: String)? {
    if let target = knownMetadata?.target, let id = target.id?.nonEmpty,
      let raw = target.targetType, let targetMode = RandomizerMode(spinTargetType: raw),
      targetMode == mode { return (targetMode, id) }
    if mode == .diamond, let project = project?.nonEmpty { return (.diamond, project) }
    return nil
  }
  private var knownMetadata: ReadMetadata? {
    guard let metadata, metadata.version == 1,
      metadata.mode == nil || RandomizerMode(spinWireValue: metadata.mode!) != nil else { return nil }
    return metadata
  }

  enum CodingKeys: String, CodingKey {
    case id, user, project, metadata
    case projectTitle = "project_title"
    case spunAt = "spun_at"
    case selectedProjects = "selected_projects"
    case selectedCount = "selected_count"
    case projectCompany = "project_company"
    case projectArtist = "project_artist"
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    user = try values.decode(String.self, forKey: .user)
    projectTitle = try values.decode(String.self, forKey: .projectTitle)
    spunAt = try values.decode(String.self, forKey: .spunAt)
    project = try? values.decode(String.self, forKey: .project)
    selectedProjects = try? values.decode([String].self, forKey: .selectedProjects)
    selectedCount = try? values.decode(Int.self, forKey: .selectedCount)
    projectCompany = try? values.decode(String.self, forKey: .projectCompany)
    projectArtist = try? values.decode(String.self, forKey: .projectArtist)
    metadata = try? values.decode(ReadMetadata.self, forKey: .metadata)
  }

  private struct ReadMetadata: Decodable, Equatable, Sendable {
    let version: Int?
    let mode: String?
    let target: ReadTarget?
    let selectedTargetIds: [String]?
    enum CodingKeys: String, CodingKey { case version, mode, target, selectedTargetIds }
    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      version = try? values.decode(Int.self, forKey: .version)
      mode = try? values.decode(String.self, forKey: .mode)
      target = try? values.decode(ReadTarget.self, forKey: .target)
      selectedTargetIds = try? values.decode([String].self, forKey: .selectedTargetIds)
    }
  }

  private struct ReadTarget: Decodable, Equatable, Sendable {
    let id: String?
    let targetType: String?
    let title: String?
    let subtitle: String?
    enum CodingKeys: String, CodingKey { case id, targetType, title, subtitle }
    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      id = try? values.decode(String.self, forKey: .id)
      targetType = try? values.decode(String.self, forKey: .targetType)
      title = try? values.decode(String.self, forKey: .title)
      subtitle = try? values.decode(String.self, forKey: .subtitle)
    }
  }
}

struct SpinHistoryCreate: Encodable, Sendable {
  let user: String
  let project: String?
  let projectTitle: String
  let spunAt: String
  let selectedProjects: [String]
  let selectedCount: Int
  let projectCompany: String?
  let projectArtist: String?
  let metadata: Metadata

  enum CodingKeys: String, CodingKey {
    case user, project, metadata
    case projectTitle = "project_title"
    case spunAt = "spun_at"
    case selectedProjects = "selected_projects"
    case selectedCount = "selected_count"
    case projectCompany = "project_company"
    case projectArtist = "project_artist"
  }

  init(selection: RandomizerSelection, userID: String, completedAt: Date) {
    user = userID
    project = selection.mode == .diamond ? selection.winner.item.recordID : nil
    projectTitle = Self.snapshot(selection.winner, mode: selection.mode).title
    spunAt = completedAt.ISO8601Format(.init(includingFractionalSeconds: true))
    selectedProjects = selection.candidates.map(\.item.recordID)
    selectedCount = selectedProjects.count
    if case .diamond(let record) = selection.winner.item {
      projectCompany = (record.expand?.company?.name).flatMap { $0.count <= 100 ? $0 : nil }
      projectArtist = (record.expand?.artist?.name).flatMap { $0.count <= 100 ? $0 : nil }
    } else { projectCompany = nil; projectArtist = nil }
    metadata = Metadata(selection: selection)
  }

  struct Target: Encodable, Sendable {
    let id: String
    let targetType: String
    let title: String
    let subtitle: String
  }
  struct LinkedTarget: Encodable, Sendable {
    let id: String
    let targetType: String
    let title: String
    let subtitle: String
    let href: String
  }
  struct Eligibility: Encodable, Sendable {
    let diamondStatuses: [String]
    let bookStatuses: [String]
    let pageStatuses: [String]
    let ownership = "owned"
  }
  struct Metadata: Encodable, Sendable {
    let version = 1
    let mode: String
    let target: LinkedTarget
    let eligibility: Eligibility
    let selectedTargetIds: [String]
    let selectedTargets: [Target]

    init(selection: RandomizerSelection) {
      mode = selection.mode.spinWireValue
      let winner = Self.target(selection.winner, mode: selection.mode)
      target = winner
      eligibility = Eligibility(
        diamondStatuses: selection.eligibility.statuses(for: .diamond),
        bookStatuses: selection.eligibility.statuses(for: .book),
        pageStatuses: selection.eligibility.statuses(for: .page))
      selectedTargetIds = selection.candidates.map(\.item.recordID)
      selectedTargets = selection.candidates.map { SpinHistoryCreate.snapshot($0, mode: selection.mode) }
    }

    private static func target(_ candidate: RandomizerCandidate, mode: RandomizerMode) -> LinkedTarget {
      let value = SpinHistoryCreate.snapshot(candidate, mode: mode)
      let href: String
      switch candidate.item {
      case .diamond(let project): href = "/projects/\(project.id)"
      case .book(let book): href = "/coloring/\(book.id)"
      case .page(let page): href = "/coloring/\(page.book)/pages/\(page.id)"
      }
      return LinkedTarget(id: value.id, targetType: value.targetType,
        title: value.title, subtitle: value.subtitle, href: href)
    }
  }

  private static func snapshot(_ candidate: RandomizerCandidate, mode: RandomizerMode) -> Target {
    let title: String
    let subtitle: String
    switch candidate.item {
    case .diamond(let project):
      title = candidate.title
      subtitle = [project.expand?.company?.name, project.expand?.artist?.name]
        .compactMap { $0?.nonEmpty }.joined(separator: " · ")
    case .book(let book):
      title = candidate.title
      subtitle = [book.expand?.publisher?.name, book.expand?.illustrator?.name]
        .compactMap { $0?.nonEmpty }.joined(separator: " · ")
    case .page(let page):
      title = candidate.bookTitle.map { "\($0), page \(page.pageNumber)" } ?? candidate.title
      subtitle = candidate.bookTitle ?? ""
    }
    return Target(id: candidate.item.recordID, targetType: mode.spinTargetType,
      title: title, subtitle: subtitle)
  }
}

struct RandomizerEligibility: Equatable, Sendable {
  let included: [RandomizerMode: Set<String>]

  init(mode: RandomizerMode, statuses: Set<String>, configured: [RandomizerMode: Set<String>]? = nil) {
    var included = configured ?? [:]
    included[mode] = statuses
    self.included = included
  }

  func statuses(for mode: RandomizerMode) -> [String] {
    let values = included[mode] ?? mode.defaultStatuses
    return mode.eligibleStatuses.filter { values.contains($0) }
  }
}
