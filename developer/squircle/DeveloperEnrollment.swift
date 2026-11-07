import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum DeveloperPolicy {
    static let coordinator = "mcp:launch:35d158297e1521e6b8760d9a70706a8e48f4b0ced66ea511a4f48fe9b37b9ac3"
    static let projects = ["90467d1d-7979-4839-b147-d1f2aae30573", "66f71ea9-e4b3-44d3-813f-ae6739c23a2a"]
}

@MainActor
enum DeveloperEnrollment {
    private static var window: UIWindow?
    private static var launcher: UIWindow?
    private static var observer: NSObjectProtocol?
    static func present() {
        guard Bundle.main.bundleIdentifier == "com.interactivebuffoonery.organizedglitter" else { return }
        guard window == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { show() }
        }
        show()
    }
    private static func show() {
        guard window == nil, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) else { return }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        OverlayHost.shared.end()
        launcher?.isHidden = true
        launcher = nil
        let sheet = UIWindow(windowScene: scene)
        sheet.windowLevel = .alert + 2
        sheet.rootViewController = UIHostingController(rootView: EnrollmentView())
        window = sheet
        sheet.makeKeyAndVisible()
    }
    static func connect() throws {
        let configuration = try AppConfiguration.Shared.load()
        window?.isHidden = true
        window = nil
        OverlayHost.shared.start(bundleID: Bundle.main.bundleIdentifier!, configuration: configuration)
    }
    static func dismiss() {
        guard let scene = window?.windowScene else { return }
        window?.isHidden = true
        window = nil
        let button = UIWindow(windowScene: scene)
        button.frame = CGRect(x: scene.coordinateSpace.bounds.width - 150, y: 64, width: 140, height: 44)
        button.windowLevel = .alert + 1
        button.rootViewController = UIHostingController(rootView: Button("Developer tools") { present() }.buttonStyle(.borderedProminent))
        launcher = button
        button.isHidden = false
    }
}

private struct EnrollmentView: View {
    @State private var importing = false
    @State private var status = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Personal developer connection") {
                    Text("Connect to your existing coding coordinator. Screenshots you attach are sent with your message. Review them for private information before sending.")
                    Text("This connection uses a separate, device-only Keychain item. It grants access to your Mac; import only your own HTTPS connection file.")
                    Button("Import connection file") { importing = true }
                    Button("Connect") {
                        do { try DeveloperEnrollment.connect() }
                        catch { status = "Connection unavailable. Import a current enrollment file." }
                    }
                    Button("Forget connection", role: .destructive) {
                        do {
                            try AppConfiguration.Shared.forget()
                            status = "Connection removed from this device."
                        } catch { status = "Could not remove connection. Try again while the device is unlocked." }
                    }
                    Button("Continue without developer tools") { DeveloperEnrollment.dismiss() }
                    Text(status).accessibilityLiveRegion(.polite)
                }
            }
            .navigationTitle("Developer tools")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let granted = url.startAccessingSecurityScopedResource()
                    defer { if granted { url.stopAccessingSecurityScopedResource() } }
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 65536 else { throw ClientError.configuration }
                    let data = try Data(contentsOf: url)
                    _ = try JSONDecoder().decode(AppConfiguration.self, from: data)
                    guard AppConfiguration.Shared.store(data) == .stored else { throw ClientError.configuration }
                    status = "Connection saved. Tap Connect when ready."
                } catch { status = "Could not import a valid HTTPS connection file." }
            }
        }
    }
}
