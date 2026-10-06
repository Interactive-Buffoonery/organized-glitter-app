import CoreFoundation
import Foundation
import PostHog

enum AnalyticsEvent: String, Sendable {
  case appOpened = "app_opened"
  case loginSucceeded = "auth_login_succeeded"
  case screenViewed = "screen_viewed"
  case recordOpened = "library_record_opened"
  case pagesSortChanged = "coloring_pages_sort_changed"
  case pagesFilterChanged = "coloring_pages_filter_changed"
  case projectOpened = "dashboard_project_opened"
  case searchPerformed = "dashboard_search_performed"
  case booksSearchPerformed = "coloring_books_search_performed"
  case sortChanged = "dashboard_sort_changed"
  case booksSortChanged = "coloring_books_sort_changed"
  case filterChanged = "dashboard_status_segment_clicked"
  case booksFilterChanged = "coloring_books_filter_changed"
  case craftChanged = "dashboard_mode_changed"
  case recordSavedLocally = "library_record_saved_locally"
  case projectCreated = "project_created"
  case projectUpdated = "project_updated"
  case projectDeleted = "project_deleted"
  case projectStatusChanged = "project_status_changed"
  case bookCreated = "coloring_book_created"
  case bookUpdated = "coloring_book_updated"
  case bookDeleted = "coloring_book_deleted"
  case bookStatusChanged = "coloring_book_status_changed"
  case pageUpdated = "coloring_page_updated"
  case pageStatusChanged = "coloring_page_status_changed"
  case noteAdded = "progress_note_added"
  case noteUpdated = "progress_note_updated"
  case noteDeleted = "progress_note_deleted"
  case pageNoteAdded = "coloring_page_progress_note_added"
  case pageNoteUpdated = "coloring_page_progress_note_updated"
  case pageNoteDeleted = "coloring_page_progress_note_deleted"
  case photoAdded = "record_photo_added"
  case photoDeleted = "record_photo_deleted"
  case pagePhotoAdded = "coloring_page_photo_added"
  case syncRequested = "library_sync_requested"
  case syncCompleted = "library_sync_completed"
  case syncFailed = "library_sync_failed"
  case syncAccepted = "library_sync_accepted"
  case syncConflict = "library_sync_conflict"
  case syncRejected = "library_sync_rejected"
  case conflictReviewOpened = "library_conflict_review_opened"
  case conflictResolved = "library_conflict_resolved"
  case accountUpdated = "account_preferences_updated"
  case verticalsUpdated = "vertical_preferences_updated"
  case companyCreated = "company_created"
  case companyUpdated = "company_updated"
  case companyDeleted = "company_deleted"
  case artistCreated = "artist_created"
  case artistUpdated = "artist_updated"
  case artistDeleted = "artist_deleted"
  case tagUpdated = "tag_updated"
  case tagDeleted = "tag_deleted"
  case publisherCreated = "book_publisher_created"
  case illustratorCreated = "book_illustrator_created"
  case mediumCreated = "coloring_medium_created"
  case mediumUpdated = "coloring_medium_updated"
  case mediumDeleted = "coloring_medium_deleted"
  case listEntryCreated = "library_list_entry_created"
  case listEntryUpdated = "library_list_entry_updated"
  case listEntryDeleted = "library_list_entry_deleted"
  case recordTagAdded = "record_tag_added"
  case recordTagRemoved = "record_tag_removed"
  case signOutRequested = "auth_logout_requested"

  var propertyKeys: Set<String> {
    switch self {
    case .appOpened, .signOutRequested: []
    case .loginSucceeded: ["auth_method", "auth_provider", "auth_entrypoint"]
    case .screenViewed: ["screen"]
    case .projectOpened, .recordOpened, .craftChanged: ["record_type"]
    case .searchPerformed, .booksSearchPerformed: ["record_type", "result_count"]
    case .sortChanged, .booksSortChanged, .pagesSortChanged: ["record_type", "sort"]
    case .filterChanged, .booksFilterChanged, .pagesFilterChanged: ["record_type", "filter_active"]
    case .recordSavedLocally: ["record_type", "field_count", "status_changed"]
    case .syncRequested, .syncCompleted, .syncFailed, .conflictReviewOpened: ["pending_count"]
    case .syncAccepted, .syncConflict, .syncRejected: ["record_type", "field_count"]
    case .conflictResolved: ["record_type", "resolution"]
    case .accountUpdated: ["setting"]
    case .verticalsUpdated: ["diamond_painting", "coloring_books"]
    case .companyCreated, .companyUpdated, .companyDeleted, .artistCreated, .artistUpdated,
      .artistDeleted, .tagUpdated, .tagDeleted, .publisherCreated, .illustratorCreated,
      .mediumCreated, .mediumUpdated, .mediumDeleted, .listEntryCreated, .listEntryUpdated,
      .listEntryDeleted: ["list_kind", "save_destination"]
    case .noteAdded, .pageNoteAdded: ["record_type", "save_destination", "has_photo"]
    default: ["record_type", "save_destination"]
    }
  }
}

enum AnalyticsRecordAction {
  case created, updated, deleted, statusChanged

  func event(collection: String) -> AnalyticsEvent? {
    switch (collection, self) {
    case ("projects", .created): .projectCreated
    case ("projects", .updated): .projectUpdated
    case ("projects", .deleted): .projectDeleted
    case ("projects", .statusChanged): .projectStatusChanged
    case ("coloring_books", .created): .bookCreated
    case ("coloring_books", .updated): .bookUpdated
    case ("coloring_books", .deleted): .bookDeleted
    case ("coloring_books", .statusChanged): .bookStatusChanged
    case ("coloring_pages", .updated): .pageUpdated
    case ("coloring_pages", .statusChanged): .pageStatusChanged
    case ("progress_notes", .created): .noteAdded
    case ("progress_notes", .updated): .noteUpdated
    case ("progress_notes", .deleted): .noteDeleted
    case ("coloring_page_progress_notes", .created): .pageNoteAdded
    case ("coloring_page_progress_notes", .updated): .pageNoteUpdated
    case ("coloring_page_progress_notes", .deleted): .pageNoteDeleted
    case ("companies", .created): .companyCreated
    case ("companies", .updated): .companyUpdated
    case ("companies", .deleted): .companyDeleted
    case ("artists", .created): .artistCreated
    case ("artists", .updated): .artistUpdated
    case ("artists", .deleted): .artistDeleted
    case ("tags", .updated), ("coloring_tags", .updated): .tagUpdated
    case ("tags", .deleted), ("coloring_tags", .deleted): .tagDeleted
    case ("book_publishers", .created): .publisherCreated
    case ("book_illustrators", .created): .illustratorCreated
    case ("coloring_mediums", .created): .mediumCreated
    case ("coloring_mediums", .updated): .mediumUpdated
    case ("coloring_mediums", .deleted): .mediumDeleted
    case ("project_tags", .created), ("coloring_book_tags", .created): .recordTagAdded
    case ("project_tags", .deleted), ("coloring_book_tags", .deleted): .recordTagRemoved
    default:
      if ListKind.allCases.contains(where: { $0.collection == collection }) {
        switch self {
        case .created: .listEntryCreated
        case .updated: .listEntryUpdated
        case .deleted: .listEntryDeleted
        case .statusChanged: nil
        }
      } else { nil }
    }
  }
}

enum AnalyticsPayload {
  static func properties(_ input: [String: Any], for event: AnalyticsEvent) -> [String: Any] {
    var result: [String: Any] = [:]
    let enums: [String: Set<String>] = [
      "list_kind": Set(ListKind.allCases.map(\.rawValue)),
      "auth_method": ["password", "oauth"],
      "auth_provider": ["email", "apple", "google", "discord"],
      "auth_entrypoint": ["login"],
      "screen": ["home", "library", "notes", "search", "account", "shelf"],
      "record_type": ["projects", "coloring_books", "coloring_pages"],
      "sort": Set(LibrarySort.allCases.map(\.rawValue)),
      "save_destination": ["server"],
      "resolution": ["keep_local", "use_server"],
      "setting": ["profile", "theme", "palette", "timezone"],
    ]
    for key in event.propertyKeys {
      guard let value = input[key] else { continue }
      if let allowed = enums[key], let value = value as? String, allowed.contains(value) {
        result[key] = value
      } else if ["result_count", "field_count", "pending_count"].contains(key),
        let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
        number.doubleValue.isFinite, number.doubleValue.rounded(.towardZero) == number.doubleValue,
        (0...10_000).contains(number.doubleValue) {
        result[key] = number.intValue
      } else if ["status_changed", "filter_active", "has_photo", "diamond_painting", "coloring_books"].contains(key),
        let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
        result[key] = number.boolValue
      }
    }
    return result
  }

  static func sanitize(_ event: PostHogEvent, configuration: AnalyticsConfiguration) -> PostHogEvent? {
    guard AnalyticsEvent(rawValue: event.event) != nil || event.event == "$identify" else {
      return nil
    }
    var properties: [String: Any] = [
      "platform": "ios",
      "environment": configuration.environment.rawValue,
      "app_version": configuration.appVersion,
      "$geoip_disable": true,
    ]
    for key in ["$lib", "$lib_version", "$session_id", "$is_identified", "$process_person_profile"] {
      if let value = event.properties[key] { properties[key] = value }
    }
    if event.event == "$identify", let anonymousID = event.properties["$anon_distinct_id"] as? String {
      properties["$anon_distinct_id"] = anonymousID
    }
    if let registered = AnalyticsEvent(rawValue: event.event) {
      properties.merge(Self.properties(event.properties, for: registered)) { _, value in value }
    }
    event.properties = properties
    return event
  }
}
