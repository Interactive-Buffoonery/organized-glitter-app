import Foundation

struct AnalyticsConfiguration: Sendable {
  enum Environment: String, Sendable {
    case production
    case preview
  }

  let projectToken: String
  let host: URL
  let environment: Environment
  let appVersion: String

  static func load(
    bundle: Bundle = .main,
    isDebug: Bool,
    arguments: [String] = ProcessInfo.processInfo.arguments,
    isTesting: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  ) -> AnalyticsConfiguration? {
    guard !isTesting,
      !arguments.contains(where: { $0.hasPrefix("-ui-testing") || $0 == "-overview-fixture" })
    else {
      return nil
    }
    return parse(
      projectToken: bundle.object(forInfoDictionaryKey: "PostHogProjectToken") as? String,
      host: bundle.object(forInfoDictionaryKey: "PostHogHost") as? String,
      environment: bundle.object(forInfoDictionaryKey: "AnalyticsEnvironment") as? String,
      appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
      isDebug: isDebug
    )
  }

  static func parse(
    projectToken: String?, host: String?, environment: String?, appVersion: String?, isDebug: Bool
  ) -> AnalyticsConfiguration? {
    guard let token = projectToken?.trimmingCharacters(in: .whitespacesAndNewlines),
      token.hasPrefix("phc_"), !token.contains("$("),
      let host, let url = URL(string: host), url.scheme == "https", url.host != nil,
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
      let environment = environment.flatMap(Environment.init(rawValue:)),
      !(isDebug && environment == .production)
    else { return nil }
    return AnalyticsConfiguration(
      projectToken: token, host: url, environment: environment,
      appVersion: appVersion ?? "unknown"
    )
  }
}
