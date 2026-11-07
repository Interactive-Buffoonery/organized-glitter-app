import Foundation

/// Audited against the locked PostHog 3.90.1 PostHogStorage.StorageKey list.
/// close/reset stop memory collection but deliberately retain durable queues.
enum PostHogLocalStorage {
  static let storageNames = [
    "posthog.distinctId", "posthog.anonymousId", "posthog.queueFolder.uuid",
    "posthog.queueFolder", "posthog.queue.plist", "posthog.replayFolder.uuid",
    "posthog.replayFolder", "posthog.replayBufferFolder", "posthog.logsFolder",
    "posthog.enabledFeatureFlags", "posthog.enabledFeatureFlagPayloads", "posthog.flags",
    "posthog.groups", "posthog.registerProperties", "posthog.optOut", "posthog.sessionReplay",
    "posthog.isIdentified", "posthog.enabledPersonProcessing", "posthog.remoteConfig",
    "posthog.surveyProgress", "posthog.surveyResetEpoch", "posthog.surveySeen",
    "posthog.lastSeenSurveyDate", "posthog.requestId", "posthog.evaluatedAt",
    "posthog.minimalFlagCalledEvents", "posthog.personPropertiesForFlags",
    "posthog.groupPropertiesForFlags", "posthog.errorTracking", "posthog.deviceId",
    "posthog.pushSubscription", "posthog.pushPendingUnregister", "posthog.pushAppIdsMigrated",
    "posthog.personPropertiesHash", "posthog.surveyState.lock", "posthog.surveyResetRevoked",
  ]

  static func erase(projectToken: String?, root: URL? = nil) throws {
    guard projectToken.map({ !$0.isEmpty && !$0.contains("/") && !$0.contains("\\") && $0 != "." && $0 != ".." }) != false,
      let bundleID = Bundle.main.bundleIdentifier else {
      throw APIError.decoding
    }
    let root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: bundleID)
    // The SDK migrates these exact legacy files from the bundle directory.
    let manager = FileManager.default
    guard manager.fileExists(atPath: root.path) else { return }
    var tokenDirectories = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
      .filter { $0.lastPathComponent.hasPrefix("phc_") && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    if let projectToken { tokenDirectories.append(root.appending(path: projectToken)) }
    for directory in [root] + Array(Set(tokenDirectories)) {
      for name in storageNames {
        let file = directory.appending(path: name)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
      }
    }
  }
}
