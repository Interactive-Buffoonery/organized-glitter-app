import Foundation
import PostHog

enum AnalyticsEvent: String, Sendable {
  case appOpened = "app_opened"
}

enum AnalyticsPayload {
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
    event.properties = properties
    return event
  }
}
