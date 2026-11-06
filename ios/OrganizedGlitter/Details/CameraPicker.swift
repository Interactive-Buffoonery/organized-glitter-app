import AVFoundation
import SwiftUI
import UIKit

struct CameraPicker: View {
  let onFinish: (UIImage?) -> Void
  @Environment(\.openURL) private var openURL
  @State private var isAuthorized = false
  @State private var isCheckingPermission = true

  var body: some View {
    Group {
      if isCheckingPermission {
        ProgressView("Checking camera access…")
      } else if isAuthorized {
        SystemCameraPicker(onFinish: onFinish)
          .ignoresSafeArea()
      } else {
        ContentUnavailableView {
          Label("Camera access needed", systemImage: "camera")
        } description: {
          Text("Allow camera access in Settings to take a photo.")
        } actions: {
          Button("Open Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
          }
          Button("Cancel", role: .cancel) { onFinish(nil) }
        }
      }
    }
    .task {
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized: isAuthorized = true
      case .notDetermined: isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
      default: isAuthorized = false
      }
      isCheckingPermission = false
    }
  }
}

/// The system camera for project and symbol photos.
private struct SystemCameraPicker: UIViewControllerRepresentable {
  let onFinish: (UIImage?) -> Void

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

  @MainActor
  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let onFinish: (UIImage?) -> Void

    init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

    func imagePickerController(_ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
      onFinish(info[.originalImage] as? UIImage)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
  }
}
