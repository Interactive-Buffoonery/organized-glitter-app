import Foundation
import Observation
import PostHog

@MainActor
@Observable
final class NativeAnalytics {
  private static let preferenceKey = "analytics.usageEnabled"
  private let defaults: UserDefaults
  @ObservationIgnored private let configuration: AnalyticsConfiguration?
  @ObservationIgnored private let sdk: PostHogSDK
  @ObservationIgnored private let gate: AnalyticsNetworkGate?
  @ObservationIgnored private let compression: PostHogCompression
  @ObservationIgnored private var started = false
  @ObservationIgnored private var accountID: String?
  @ObservationIgnored private var sessionActive = false
  private(set) var isEnabled: Bool

  init(
    configuration: AnalyticsConfiguration? = nil,
    defaults: UserDefaults = .standard,
    sdk: PostHogSDK = .shared,
    sessionConfiguration: URLSessionConfiguration = .ephemeral,
    compression: PostHogCompression = .gzip
  ) {
    self.configuration = configuration
    self.defaults = defaults
    self.sdk = sdk
    self.compression = compression
    isEnabled = defaults.object(forKey: Self.preferenceKey) as? Bool ?? true
    gate = configuration.map { AnalyticsNetworkGate(host: $0.host, sessionConfiguration: sessionConfiguration) }
  }

  func setEnabled(_ enabled: Bool) {
    guard enabled != isEnabled else { return }
    if !enabled {
      gate?.setEnabled(false)
      if started { sdk.optOut() }
    }
    defaults.set(enabled, forKey: Self.preferenceKey)
    isEnabled = enabled
    if enabled { activate() }
  }

  func setSession(accountID id: String?, isActive: Bool) {
    guard accountID != id || sessionActive != isActive else { return }
    gate?.setEnabled(false)
    if started, !isActive { sdk.optOut() }
    if started, accountID != id {
      sdk.reset()
      if !isEnabled { sdk.optOut() }
    }
    accountID = id
    sessionActive = isActive
    activate()
  }

  func capture(_ event: AnalyticsEvent) {
    guard isEnabled, sessionActive else { return }
    activate()
    guard started else { return }
    sdk.capture(event.rawValue)
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
      started = true
    }
    sdk.optIn()
    if let accountID { sdk.identify(accountID) }
    gate.setEnabled(true)
  }
}
