import SwiftUI

struct ProfileNameView: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable var preferences: AccountPreferencesModel
  @State private var name = ""

  var body: some View {
    Form {
      TextField("Profile name", text: $name)
        .textContentType(.nickname)
        .autocorrectionDisabled()
        .accessibilityLabel("Profile name")
    }
    .navigationTitle("Profile Name")
    .toolbar {
      Button("Save") {
        Task {
          if await preferences.updateProfile(username: name) {
            dismiss()
          }
        }
      }
      .disabled(
        preferences.isSaving
          || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .accessibilityLabel("Save profile name")
    }
    .onAppear {
      name = preferences.user.username ?? preferences.user.name ?? ""
    }
  }
}

struct AppInformationView: View {
  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "Unknown"
  }

  private var build: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
  }

  var body: some View {
    List {
      LabeledContent("App", value: "Organized Glitter")
      LabeledContent("Version", value: version)
      LabeledContent("Build", value: build)
      Text("A private craft-project library for iPhone and iPad.")
        .fixedSize(horizontal: false, vertical: true)
    }
    .navigationTitle("App Information")
  }
}

enum AccountLinks {
  static let privacy = URL(string: "https://organizedglitter.app/privacy")!
  static let terms = URL(string: "https://organizedglitter.app/terms")!
  static let support = URL(string: "mailto:support@organizedglitter.app")!
  static let accountDeletionSupport = URL(
    string: "mailto:support@organizedglitter.app?subject=Account%20Deletion%20Help"
  )!
  static let feedback = URL(
    string:
      "mailto:support@organizedglitter.app?subject=Organized%20Glitter%20iOS%20Feedback"
  )!
}
