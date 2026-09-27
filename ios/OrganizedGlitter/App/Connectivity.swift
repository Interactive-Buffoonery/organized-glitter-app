import Network
import Observation
import SwiftUI

private struct ConnectionAvailableKey: EnvironmentKey {
  static let defaultValue = true
}

extension EnvironmentValues {
  var connectionAvailable: Bool {
    get { self[ConnectionAvailableKey.self] }
    set { self[ConnectionAvailableKey.self] = newValue }
  }
}

@MainActor
@Observable
final class Connectivity {
  private(set) var connectionAvailable = true

  func monitor() async {
    let monitor = NWPathMonitor()
    let updates = AsyncStream<Bool> { continuation in
      monitor.pathUpdateHandler = { path in
        continuation.yield(path.status == .satisfied)
      }
      continuation.onTermination = { _ in monitor.cancel() }
      monitor.start(queue: DispatchQueue(label: "OrganizedGlitter.connectionHint"))
    }
    defer { monitor.cancel() }
    for await available in updates {
      guard !Task.isCancelled else { return }
      connectionAvailable = available
    }
  }
}

struct NeedsConnectionHint: View {
  @Environment(\.connectionAvailable) private var connectionAvailable
  @Environment(\.theme) private var theme

  var body: some View {
    if !connectionAvailable {
      Label("Needs a connection", systemImage: "wifi.slash")
        .font(.footnote)
        .foregroundStyle(theme.mutedForeground)
        .accessibilityIdentifier("connection.required")
    }
  }
}
