import SwiftUI

struct AccountView: View {
  @Environment(ThemeStore.self) private var themeStore
  @Environment(\.theme) private var theme

  let appModel: AppModel
  let client: PocketBaseClient
  @Bindable var preferences: AccountPreferencesModel

  var body: some View {
    List {
      Group {
        Section("Profile") {
          NavigationLink {
            ProfileNameView(preferences: preferences)
          } label: {
            LabeledContent(
              "Profile name",
              value: preferences.user.username ?? preferences.user.name ?? "Not set")
          }
          .accessibilityLabel("Edit profile name")

          LabeledContent("Email", value: preferences.user.email ?? "Hidden")
        }

        Section("Appearance") {
          Picker(
            "Theme",
            selection: Binding(
              get: { ThemeFlavor(rawValue: preferences.user.themePreference ?? "") ?? themeStore.flavor },
              set: { flavor in saveTheme(flavor) }
            )
          ) {
            ForEach(ThemeFlavor.allCases) { flavor in
              Text(flavor.label).tag(flavor)
            }
          }
          .pickerStyle(.segmented)
          .disabled(preferences.isSaving)
          .accessibilityLabel("Account theme")

          Picker(
            "Time zone",
            selection: Binding(
              get: { preferences.user.timezone ?? TimeZone.current.identifier },
              set: { identifier in saveTimezone(identifier) }
            )
          ) {
            ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { identifier in
              Text(identifier.replacingOccurrences(of: "_", with: " ")).tag(identifier)
            }
          }
          .disabled(preferences.isSaving)
          .accessibilityLabel("Account time zone")
        }

        Section {
          Toggle(
            "Diamond painting",
            isOn: verticalBinding(\.diamondPainting)
          )
          .disabled(preferences.isSaving || (preferences.verticals.diamondPainting && !preferences.verticals.coloringBooks))
          .accessibilityLabel("Enable diamond painting")

          Toggle(
            "Coloring",
            isOn: verticalBinding(\.coloringBooks)
          )
          .disabled(preferences.isSaving || (preferences.verticals.coloringBooks && !preferences.verticals.diamondPainting))
          .accessibilityLabel("Enable coloring")
        } header: {
          Text("Crafts")
        } footer: {
          Text("At least one craft stays enabled. Turning one off hides its Library and Create choices without deleting anything.")
        }

        Section("Help and legal") {
          Link("Support", destination: AccountLinks.support)
            .accessibilityLabel("Email Organized Glitter support")
          Link("Send feedback", destination: AccountLinks.feedback)
            .accessibilityLabel("Email Organized Glitter feedback")
          Link("Privacy", destination: AccountLinks.privacy)
            .accessibilityLabel("Open privacy policy")
          Link("Terms", destination: AccountLinks.terms)
            .accessibilityLabel("Open terms of service")
          NavigationLink("App information") {
            AppInformationView()
          }
        }

        Section("Security") {
          NavigationLink("Reset password") {
            PasswordResetView(client: client, initialEmail: preferences.user.email ?? "")
          }
          Link("Account deletion help", destination: AccountLinks.accountDeletionSupport)
            .accessibilityLabel("Email support about account deletion")
        }

        if let error = preferences.errorMessage {
          Section {
            Label(error, systemImage: "exclamationmark.circle")
              .foregroundStyle(theme.destructive)
              .accessibilityLabel("Account error: \(error)")
          }
        }

        Section {
          Button("Sign Out", role: .destructive) {
            appModel.signOut()
          }
          .accessibilityLabel("Sign out of Organized Glitter")
        }
      }
      .listRowBackground(theme.card)
    }
    .themedScrollBackground()
    .navigationTitle("Account")
    .refreshable { await preferences.load() }
    .overlay {
      if preferences.isLoading && preferences.user == .preview {
        ProgressView("Loading account")
      }
    }
  }

  private func saveTheme(_ flavor: ThemeFlavor) {
    Task {
      if await preferences.updateTheme(flavor) {
        themeStore.flavor = flavor
      }
    }
  }

  private func saveTimezone(_ identifier: String) {
    Task { _ = await preferences.updateTimezone(identifier) }
  }

  private func verticalBinding(_ keyPath: WritableKeyPath<VerticalPreferences, Bool>) -> Binding<Bool> {
    Binding(
      get: { preferences.verticals[keyPath: keyPath] },
      set: { enabled in
        var next = preferences.verticals
        next[keyPath: keyPath] = enabled
        Task { _ = await preferences.updateVerticals(next) }
      }
    )
  }
}
