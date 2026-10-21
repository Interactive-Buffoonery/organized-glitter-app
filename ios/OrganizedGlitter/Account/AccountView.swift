import SwiftUI

struct AccountView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(ThemeStore.self) private var themeStore
  @Environment(\.theme) private var theme
  @Environment(\.connectionAvailable) private var connectionAvailable

  let appModel: AppModel
  let library: LibrarySession
  let client: PocketBaseClient
  @Bindable var preferences: AccountPreferencesModel
  @Binding var showCraftingStreak: Bool

  var body: some View {
    // A List here trips a UIKit focus assertion on iPad once the content
    // passes a certain height (Apple r.154431813); return to List when Apple fixes it.
    ScrollView {
      VStack(spacing: 24) {
        if !connectionAvailable {
          AccountSection {
            NeedsConnectionHint()
          }
        }

        AccountSection(title: "Profile") {
          NavigationLink {
            ProfileNameView(preferences: preferences)
          } label: {
            AccountNavigationRow {
              LabeledContent(
                "Profile name",
                value: preferences.user.username ?? preferences.user.name ?? "Not set")
            }
          }
          .accessibilityLabel("Edit profile name")

          LabeledContent("Email", value: preferences.user.email ?? "Hidden")
        }

        AccountSection(title: "Appearance") {
          AccountAppearancePicker(
            title: "Theme",
            value: selectedFlavor.label,
            selection: Binding(
              get: { ThemeFlavor(rawValue: preferences.user.themePreference ?? "") ?? themeStore.flavor },
              set: { flavor in saveTheme(flavor) }
            )
          ) {
            ForEach(ThemeFlavor.allCases) { flavor in
              Text(flavor.label).tag(flavor)
            }
          }
          .disabled(preferences.isBusy)
          .accessibilityLabel("Account theme")

          AccountAppearancePicker(
            title: "Background",
            value: selectedPalette.label,
            selection: Binding(
              get: { ThemePalette(rawValue: preferences.user.themePalette ?? "") ?? themeStore.palette },
              set: { palette in savePalette(palette) }
            )
          ) {
            ForEach(ThemePalette.allCases) { palette in
              Text(palette.label).tag(palette)
            }
          }
          .disabled(preferences.isBusy)
          .accessibilityLabel("Account background")

          if dynamicTypeSize.isAccessibilitySize {
            Menu {
              timezonePicker
            } label: {
              VStack(alignment: .leading, spacing: 8) {
                Text("Time zone")
                  .foregroundStyle(theme.foreground)
                Text(selectedTimezone.replacingOccurrences(of: "_", with: " "))
                  .fixedSize(horizontal: false, vertical: true)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel("Account time zone")
            .accessibilityValue(selectedTimezone)
            .disabled(preferences.isBusy)
          } else {
            LabeledContent("Time zone") {
              timezonePicker.labelsHidden()
            }
          }
        }

        AccountSection(
          title: "Crafts",
          footer: "At least one craft stays enabled. Turning one off hides its Library and Create choices without deleting anything."
        ) {
          Toggle(
            "Diamond painting",
            isOn: verticalBinding(\.diamondPainting)
          )
          .disabled(preferences.isBusy || (preferences.verticals.diamondPainting && !preferences.verticals.coloringBooks))
          .accessibilityLabel("Enable diamond painting")

          Toggle(
            "Coloring",
            isOn: verticalBinding(\.coloringBooks)
          )
          .disabled(preferences.isBusy || (preferences.verticals.coloringBooks && !preferences.verticals.diamondPainting))
          .accessibilityLabel("Enable coloring")
        }

        AccountSection {
          NavigationLink {
            ManageListsView(
              library: library, userID: preferences.user.id,
              verticals: preferences.verticals)
          } label: {
            AccountNavigationRow {
              Label("Manage lists", systemImage: "list.bullet")
            }
          }
        }

        AccountSection(title: "Home") {
          Toggle("Show crafting streak", isOn: Binding(
            get: { showCraftingStreak },
            set: { enabled in
              guard AccountPreferenceInteraction.changed(from: showCraftingStreak, to: enabled)
              else { return }
              showCraftingStreak = enabled
              library.captureAnalytics(
                .accountUpdated,
                properties: ["setting": AnalyticsAccountSetting.craftingStreak.rawValue])
            }
          ))
            .accessibilityLabel("Show crafting streak")
            .accessibilityIdentifier("account.showCraftingStreak")
        }

        AccountSection(
          title: "Privacy",
          footer: "Usage analytics helps improve Organized Glitter. Signed-in activity is linked to your account without project content, search text, email, or name. Your account choice applies anywhere you sign in and requires a connection to save. Turning this off stops new collection here right away. You can also pause collection on this device for this session, even offline. Other open apps and browsers will pick up the change after they refresh your account. Previously collected events may still be delivered, including after you turn analytics back on. It does not delete past activity."
        ) {
          Toggle(
            "Share usage analytics",
            isOn: Binding(
              get: { preferences.user.analyticsOptOut.map { !$0 } ?? false },
              set: { enabled in
                Task { _ = await preferences.updateAnalyticsEnabled(enabled) }
              }
            )
          )
          .disabled(
            preferences.isBusy
              || preferences.user.analyticsOptOut == nil || !connectionAvailable)
          .accessibilityIdentifier("account.usageAnalytics")

          if preferences.isAnalyticsLocallyPaused {
            Text("Analytics is paused on this device for this session. Connect to resume collection or turn sharing off for your account.")
              .accessibilityIdentifier("account.analyticsPaused")
            if preferences.user.analyticsOptOut == false {
              Button("Resume analytics on this device") {
                Task { _ = await preferences.updateAnalyticsEnabled(true) }
              }
              .disabled(preferences.isBusy || !connectionAvailable)
              .accessibilityIdentifier("account.resumeAnalytics")
            }
          } else {
            Button("Pause analytics on this device") {
              preferences.pauseAnalyticsLocally()
            }
            .accessibilityIdentifier("account.pauseAnalytics")
          }
        }

        AccountSection(title: "Help and legal") {
          Link("Support", destination: AccountLinks.support)
            .accessibilityLabel("Email Organized Glitter support")
          Link("Send feedback", destination: AccountLinks.feedback)
            .accessibilityLabel("Email Organized Glitter feedback")
          Link("Privacy", destination: AccountLinks.privacy)
            .accessibilityLabel("Open privacy policy")
          Link("Terms", destination: AccountLinks.terms)
            .accessibilityLabel("Open terms of service")
          NavigationLink {
            AppInformationView()
          } label: {
            AccountNavigationRow { Text("App information") }
          }
        }

        AccountSection(title: "Security") {
          NavigationLink {
            PasswordResetView(client: client, initialEmail: preferences.user.email ?? "")
          } label: {
            AccountNavigationRow { Text("Reset password") }
          }
          Link("Account deletion help", destination: AccountLinks.accountDeletionSupport)
            .accessibilityLabel("Email support about account deletion")
        }

        if let error = preferences.errorMessage {
          AccountSection {
            Label(error, systemImage: "exclamationmark.circle")
              .foregroundStyle(theme.destructive)
              .accessibilityLabel("Account error: \(error)")
          }
        }

        AccountSection {
          Button("Sign Out", role: .destructive) {
            appModel.signOut()
          }
          .accessibilityLabel("Sign out of Organized Glitter")
          .disabled(appModel.isSigningOut)
          if let message = appModel.sessionError { Text(message) }
        }
      }
      .buttonStyle(AccountRowStyle())
      .padding(.vertical, 20)
    }
    .accessibilityIdentifier("account.list")
    .themedScrollBackground()
    .navigationTitle("Account")
    .confirmationDialog(
      "There are changes saved only on this device.",
      isPresented: Binding(
        get: { appModel.requiresDiscardConfirmation },
        set: { appModel.requiresDiscardConfirmation = $0 }
      ), titleVisibility: .visible
    ) {
      Button("Discard Local Changes and Sign Out", role: .destructive) {
        appModel.signOut(discardPending: true)
      }
      Button("Keep Working", role: .cancel) {}
    } message: {
      Text("Stay signed in and synchronize to keep these changes in your account.")
    }
    .refreshable { await preferences.load() }
    .overlay {
      if preferences.isLoading && preferences.user == .preview {
        ProgressView("Loading account")
      }
    }
  }

  private var selectedFlavor: ThemeFlavor {
    ThemeFlavor(rawValue: preferences.user.themePreference ?? "") ?? themeStore.flavor
  }

  private var selectedPalette: ThemePalette {
    ThemePalette(rawValue: preferences.user.themePalette ?? "") ?? themeStore.palette
  }

  private var selectedTimezone: String {
    preferences.user.timezone ?? TimeZone.current.identifier
  }

  private var timezonePicker: some View {
    Picker(
      "Time zone",
      selection: Binding(
        get: { selectedTimezone },
        set: { identifier in saveTimezone(identifier) }
      )
    ) {
      ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { identifier in
        Text(identifier.replacingOccurrences(of: "_", with: " ")).tag(identifier)
      }
    }
    .disabled(preferences.isBusy)
    .accessibilityLabel("Account time zone")
  }

  private func saveTheme(_ flavor: ThemeFlavor) {
    Task {
      if await preferences.updateTheme(flavor) {
        themeStore.flavor = flavor
      }
    }
  }

  private func savePalette(_ palette: ThemePalette) {
    Task {
      if await preferences.updatePalette(palette) {
        themeStore.palette = palette
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

enum AccountPreferenceInteraction {
  static func changed(from current: Bool, to selection: Bool) -> Bool {
    current != selection
  }
}

private struct AccountAppearancePicker<Selection: Hashable, Options: View>: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.theme) private var theme

  let title: String
  let value: String
  @Binding var selection: Selection
  @ViewBuilder let options: Options

  var body: some View {
    if dynamicTypeSize.isAccessibilitySize {
      Menu {
        picker
      } label: {
        VStack(alignment: .leading, spacing: 8) {
          Text(title)
            .foregroundStyle(theme.foreground)
          Text(value)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .accessibilityValue(value)
    } else {
      picker.pickerStyle(.segmented)
    }
  }

  private var picker: some View {
    Picker(title, selection: $selection) { options }
  }
}

private struct AccountSection<Content: View>: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.theme) private var theme

  var title: String?
  var footer: String?
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
      if let title {
        Text(title)
          .accessibilityAddTraits(.isHeader)
          .padding(.horizontal, inset)
      }
      VStack(spacing: 0) {
        Group(subviews: content) { rows in
          ForEach(rows) { row in
            if row.id != rows.first?.id { Divider() }
            row
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
              .padding(.vertical, 6)
          }
        }
      }
      .padding(.horizontal, inset)
      .background(theme.card, in: .rect(cornerRadius: 26))
      if let footer {
        Text(footer)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, inset)
      }
    }
    .padding(.horizontal, inset)
  }

  /// The inset grouped List's margins.
  private var inset: CGFloat { horizontalSizeClass == .regular ? 20 : 16 }
}

private struct AccountNavigationRow<Label: View>: View {
  @ViewBuilder let label: Label

  var body: some View {
    HStack(spacing: Theme.Spacing.sm) {
      label
      Spacer(minLength: 0)
      Image(systemName: "chevron.right")
        .imageScale(.small)
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }
  }
}

/// Plain full-width rows, matching how the inset grouped List drew links and buttons.
private struct AccountRowStyle: ButtonStyle {
  @Environment(\.theme) private var theme
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(theme.foreground)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(.rect)
      .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.5)
  }
}
