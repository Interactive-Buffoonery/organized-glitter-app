import Foundation

enum PocketBaseFilter {
  enum Field: String {
    case user
    case status
    case title
    case name
    case book
    case project
    case projectUser = "project.user"
    case page
    case pageBookUser = "page.book.user"
    case bookUser = "book.user"
    case bookTitle = "book.title"
    case pageNumber = "page_number"
    case dateCompleted = "date_completed"
    case completedAt = "completed_at"
  }

  static func equals(_ field: Field, _ value: String) -> String {
    "\(field.rawValue) = \"\(escape(value))\""
  }

  static func contains(_ field: Field, _ value: String) -> String {
    "\(field.rawValue) ~ \"\(escape(value))\""
  }

  static func equals(_ field: Field, _ value: Int) -> String {
    "\(field.rawValue) = \(value)"
  }

  static func greaterThanOrEqual(_ field: Field, _ value: String) -> String {
    "\(field.rawValue) >= \"\(escape(value))\""
  }

  static func lessThan(_ field: Field, _ value: String) -> String {
    "\(field.rawValue) < \"\(escape(value))\""
  }

  static func all(_ filters: [String]) -> String {
    filters.filter { !$0.isEmpty }.joined(separator: " && ")
  }

  static func any(_ filters: [String]) -> String {
    let filters = filters.filter { !$0.isEmpty }
    guard filters.count > 1 else {
      return filters.first ?? ""
    }
    return "(\(filters.joined(separator: " || ")))"
  }

  private static func escape(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\r", with: "\\r")
  }
}
