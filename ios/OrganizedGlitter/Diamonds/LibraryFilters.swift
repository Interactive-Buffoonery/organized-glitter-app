import Foundation

struct LibraryFilters: Equatable {
  var companyID: String?
  var artistID: String?
  var drillShape: String?
  var completionYear: Int?
  var publisherIDs: Set<String> = []
  var illustratorIDs: Set<String> = []
  var tagIDs: Set<String> = []

  var isEmpty: Bool { self == Self() }

  var activeFacets: [String] {
    var names: [String] = []
    if companyID != nil { names.append("Company") }
    if artistID != nil { names.append("Artist") }
    if drillShape != nil { names.append("Drill shape") }
    if completionYear != nil { names.append("Finished in") }
    if !publisherIDs.isEmpty { names.append("Publisher") }
    if !illustratorIDs.isEmpty { names.append("Illustrator") }
    if !tagIDs.isEmpty { names.append("Tags") }
    return names
  }

  var identity: String {
    let values = [companyID ?? "", artistID ?? "", drillShape ?? "",
      completionYear.map(String.init) ?? ""]
      + publisherIDs.sorted() + ["|"] + illustratorIDs.sorted() + ["|"] + tagIDs.sorted()
    return values.map { "\($0.utf8.count):\($0)" }.joined()
  }

  func matches(_ item: LibraryItem) -> Bool {
    switch item {
    case .diamond(let project):
      return (companyID == nil || project.company == companyID)
        && (artistID == nil || project.artist == artistID)
        && (drillShape == nil || project.drillShape == drillShape)
        && (completionYear == nil || Self.year(in: project.dateCompleted) == completionYear)
        && (tagIDs.isEmpty || !tagIDs.isDisjoint(with: project.tags.map(\.id)))
    case .book(let book):
      return (publisherIDs.isEmpty || publisherIDs.contains(book.publisher ?? ""))
        && (illustratorIDs.isEmpty || illustratorIDs.contains(book.illustrator ?? ""))
        && (tagIDs.isEmpty || !tagIDs.isDisjoint(with: book.tags.map(\.id)))
    case .page:
      return isEmpty
    }
  }

  static func year(in value: String?) -> Int? {
    guard let value, DetailDateOnly.date(value, timeZone: TimeZone(secondsFromGMT: 0)!) != nil else { return nil }
    return Int(value.prefix(4))
  }
}

struct LibraryFilterOption: Identifiable, Equatable {
  let id: String
  let name: String
}

struct LibraryFilterOptions {
  var companies: [LibraryFilterOption] = []
  var artists: [LibraryFilterOption] = []
  var drillShapes: [LibraryFilterOption] = []
  var completionYears: [Int] = []
  var publishers: [LibraryFilterOption] = []
  var illustrators: [LibraryFilterOption] = []
  var tags: [LibraryFilterOption] = []

  init(items: [LibraryItem], section: LibrarySection, userID: String) {
    var companies: [String: String] = [:]
    var artists: [String: String] = [:]
    var drills: [String: String] = [:]
    var years: Set<Int> = []
    var publishers: [String: String] = [:]
    var illustrators: [String: String] = [:]
    var tags: [String: String] = [:]
    for item in items where item.belongs(to: section, userID: userID, bookTitles: [:]) {
      switch item {
      case .diamond(let project):
        Self.name(project.company, from: project.expand?.company, fallback: "Unavailable company",
          in: &companies)
        Self.name(project.artist, from: project.expand?.artist, fallback: "Unavailable artist",
          in: &artists)
        if let drill = project.drillShape, !drill.isEmpty { drills[drill] = drill.capitalized }
        if let year = LibraryFilters.year(in: project.dateCompleted) { years.insert(year) }
        for tag in project.tags { tags[tag.id] = tag.name }
      case .book(let book):
        Self.name(book.publisher, from: book.expand?.publisher, fallback: "Unavailable publisher",
          in: &publishers)
        Self.name(book.illustrator, from: book.expand?.illustrator,
          fallback: "Unavailable illustrator", in: &illustrators)
        for tag in book.tags { tags[tag.id] = tag.name }
      case .page: break
      }
    }
    self.companies = Self.options(companies)
    self.artists = Self.options(artists)
    drillShapes = Self.options(drills)
    completionYears = years.sorted(by: >)
    self.publishers = Self.options(publishers)
    self.illustrators = Self.options(illustrators)
    self.tags = Self.options(tags)
  }

  /// A pending offline relation edit keeps the previous expanded name, so only trust a matching ID.
  private static func name(
    _ id: String?, from expanded: NamedRelationRecord?, fallback: String,
    in names: inout [String: String]
  ) {
    guard let id, !id.isEmpty else { return }
    if let expanded, expanded.id == id {
      names[id] = expanded.name
    } else if names[id] == nil {
      names[id] = fallback
    }
  }

  private static func options(_ values: [String: String]) -> [LibraryFilterOption] {
    values.map { LibraryFilterOption(id: $0.key, name: $0.value) }.sorted {
      let comparison = $0.name.localizedStandardCompare($1.name)
      return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
    }
  }
}
