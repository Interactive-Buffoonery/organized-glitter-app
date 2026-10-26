import Photos
import SwiftUI
import UIKit

struct CameraPhotoPreference {
  static let key = "camera.savePhotosToLibrary"
  static let defaultValue = true

  static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
    defaults.object(forKey: key) as? Bool ?? defaultValue
  }
}

@MainActor
struct CameraRollSave {
  static func save(
    enabled: Bool,
    authorization: () async -> PHAuthorizationStatus,
    createAsset: () async throws -> Void
  ) async {
    guard enabled else { return }
    guard await authorization() == .authorized else { return }
    do {
      try await createAsset()
    } catch {
      // Keeping a camera-roll copy is best effort; the project photo flow continues.
    }
  }

  static func saveCapture(_ image: UIImage, enabled: Bool) async {
    await save(enabled: enabled) {
      await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    } createAsset: {
      try await PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.creationRequestForAsset(from: image)
      }
    }
  }
}

struct CameraPhotoSetting: View {
  @AppStorage(CameraPhotoPreference.key)
  private var enabled = CameraPhotoPreference.defaultValue
  @Environment(\.scenePhase) private var scenePhase
  @State private var authorization = PHPhotoLibrary.authorizationStatus(for: .addOnly)

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // UNAPPROVED copy
      Toggle("Save photos taken in the app to the camera roll", isOn: $enabled)
        // UNAPPROVED copy
        .accessibilityLabel("Save photos taken in the app to the camera roll")
        .accessibilityIdentifier("account.saveCameraPhotos")
      if enabled && (authorization == .denied || authorization == .restricted) {
        // UNAPPROVED copy
        Text("Saving camera photos needs Photos access.")
          .font(.karla(.caption))
        if let url = URL(string: UIApplication.openSettingsURLString) {
          // UNAPPROVED copy
          Link("Open Settings", destination: url)
        }
      }
    }
    .onAppear { refreshAuthorization() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { refreshAuthorization() }
    }
  }

  // Read permission again after a capture or a visit to Settings.
  private func refreshAuthorization() {
    authorization = PHPhotoLibrary.authorizationStatus(for: .addOnly)
  }
}
