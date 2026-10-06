import Foundation
import Observation
import PostHog

@MainActor
@Observable
final class NativeAnalytics {
  @ObservationIgnored private let configuration: AnalyticsConfiguration?
  @ObservationIgnored private let sdk: PostHogSDK
  @ObservationIgnored private let gate: AnalyticsNetworkGate?
  @ObservationIgnored private let compression: PostHogCompression
  @ObservationIgnored private let eventHandler: ((AnalyticsEvent, [String: Any]) -> Void)?
  @ObservationIgnored private var started = false
  @ObservationIgnored private var accountID: String?
  @ObservationIgnored private var identifiedAccountID: String?
  @ObservationIgnored private var sessionActive = false
  private(set) var isEnabled = false

  var isCollecting: Bool {
    isEnabled && configuration != nil
  }

  init(
    configuration: AnalyticsConfiguration? = nil,
    sdk: PostHogSDK = .shared,
    sessionConfiguration: URLSessionConfiguration = .ephemeral,
    compression: PostHogCompression = .gzip,
    eventHandler: ((AnalyticsEvent, [String: Any]) -> Void)? = nil
  ) {
    self.eventHandler = eventHandler
    self.configuration = configuration
    self.sdk = sdk
    self.compression = compression
    gate = configuration.map { AnalyticsNetworkGate(host: $0.host, sessionConfiguration: sessionConfiguration) }
  }

  func setSession(accountID id: String?, isActive: Bool, analyticsEnabled: Bool?) {
    let enabled = id != nil && isActive && analyticsEnabled == true
    guard accountID != id || sessionActive != isActive || isEnabled != enabled else { return }
    if !enabled || accountID != id {
      gate?.setEnabled(false)
      if started { sdk.optOut() }
    }
    if started, accountID != id {
      sdk.reset()
      identifiedAccountID = nil
      if !enabled { sdk.optOut() }
    }
    accountID = id
    sessionActive = isActive
    isEnabled = enabled
    activate()
  }

  func capture(_ event: AnalyticsEvent, properties: [String: Any] = [:], accountID expectedAccountID: String? = nil) {
    guard isEnabled, sessionActive, expectedAccountID == nil || expectedAccountID == accountID else { return }
    let safe = AnalyticsPayload.properties(properties, for: event)
    if let eventHandler {
      eventHandler(event, safe)
      return
    }
    activate()
    guard started else { return }
    sdk.capture(event.rawValue, properties: safe)
  }

  func loginSucceeded(provider: String) {
    capture(.loginSucceeded, properties: [
      "auth_method": provider == "email" ? "password" : "oauth",
      "auth_provider": provider, "auth_entrypoint": "login",
    ])
  }

  func record(
    _ action: AnalyticsRecordAction, collection: String, hasPhoto: Bool = false,
    accountID: String? = nil
  ) {
    guard let event = action.event(collection: collection) else { return }
    var properties: [String: Any] = [
      "record_type": ["progress_notes", "project_tags"].contains(collection) ? "projects"
        : collection == "coloring_page_progress_notes" ? "coloring_pages"
        : collection == "coloring_book_tags" ? "coloring_books" : collection,
      "save_destination": "server", "has_photo": hasPhoto,
    ]
    if let kind = ListKind.allCases.first(where: { $0.collection == collection }) {
      properties["list_kind"] = kind.rawValue
    }
    capture(event, properties: properties, accountID: accountID)
  }

  func synchronized(_ operation: LocalPendingOperation, accountID: String) {
    capture(.syncAccepted, properties: [
      "record_type": operation.key.kind.rawValue, "field_count": operation.patch.count,
    ], accountID: accountID)
    record(.updated, collection: operation.key.kind.rawValue, accountID: accountID)
    if let status = operation.patch["status"], status != operation.base["status"] {
      record(.statusChanged, collection: operation.key.kind.rawValue, accountID: accountID)
    }
  }

  func close() {
    gate?.setEnabled(false)
    if started { sdk.close() }
    if let gate { AnalyticsRequestProtocol.unregister(gate) }
    started = false
  }

  private func activate() {
    guard isEnabled, sessionActive, let configuration, let gate else { return }
    if !started {
      let config = PostHogConfig(projectToken: configuration.projectToken, host: configuration.host.absoluteString)
      config.captureApplicationLifecycleEvents = false
      config.captureScreenViews = false
      config.captureElementInteractions = false
      config.captureSwiftUIElementInteractions = false
      config.captureAutocaptureElementText = false
      config.capturePushNotificationSubscriptions = false
      config.capturePushNotificationOpened = false
      config.enableSwizzling = false
      config.sessionReplay = false
      config.surveys = false
      config.errorTrackingConfig.autoCapture = false
      config.errorTrackingConfig.exceptionSteps.enabled = false
      config.preloadFeatureFlags = false
      config.sendFeatureFlagEvent = false
      config.setDefaultPersonProperties = false
      config.disableGeoIp = true
      config.optOut = true
      config.maxQueueSize = 100
      config.maxBatchSize = 20
      config.compression = compression
      config.debug = false
      config.setBeforeSend { AnalyticsPayload.sanitize($0, configuration: configuration) }
      let session = URLSessionConfiguration.ephemeral
      session.protocolClasses = [AnalyticsRequestProtocol.self]
      config.urlSessionConfiguration = session
      config.requestHeaders = [AnalyticsRequestProtocol.gateHeader: gate.id]
      AnalyticsRequestProtocol.register(gate)
      sdk.setup(config)
      sdk.reset()
      identifiedAccountID = nil
      started = true
    }
    sdk.optIn()
    if let accountID, identifiedAccountID != accountID {
      sdk.identify(accountID)
      identifiedAccountID = accountID
    }
    gate.setEnabled(true)
  }
}
