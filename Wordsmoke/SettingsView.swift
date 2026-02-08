import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var themeSelectionRaw: String
  @Bindable var onboarding: OnboardingStore
  let analytics: AnalyticsService
  @AppStorage("debug.enabled") private var showDebug = false
  @AppStorage(AppEnvironment.useDevelopmentKey) private var useDevelopment =
    AppEnvironment.defaultServerEnvironment == .development
  @AppStorage(AppEnvironment.developmentURLKey) private var developmentURLRaw =
    AppEnvironment.defaultDevelopmentURL.absoluteString

  private var selection: ThemeSelection {
    ThemeSelection(rawValue: themeSelectionRaw) ?? .system
  }

  private var onboardingToggleBinding: Binding<Bool> {
    Binding(
      get: { onboarding.pendingStart },
      set: { newValue in
        if newValue {
          onboarding.requestStart()
          analytics.track(.onboardingRerunRequested, properties: ["source": "settings"])
        } else {
          onboarding.markCompleted()
        }
      }
    )
  }

  private var developerURLText: Binding<String> {
    Binding(
      get: { developmentURLRaw },
      set: { newValue in
        developmentURLRaw = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    )
  }

  private var appVersionText: String {
    let shortVersion =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    return "Version \(shortVersion) (\(buildNumber))"
  }

  var body: some View {
    let selectionBinding = Binding<ThemeSelection>(
      get: { ThemeSelection(rawValue: themeSelectionRaw) ?? .system },
      set: { themeSelectionRaw = $0.rawValue }
    )
    return NavigationStack {
      SwiftUI.Form {
        SwiftUI.Section {
          SwiftUI.Picker("Theme", selection: selectionBinding) {
            ForEach(ThemeSelection.allCases, id: \.self) { option in
              SwiftUI.Text(option.title)
                .tag(option)
            }
          }
          .pickerStyle(.inline)
          .accessibilityIdentifier("theme-picker")
        } header: {
          SwiftUI.Text("Theme")
        } footer: {
          SwiftUI.Text("System matches iOS-wide styling, including accent and dynamic colors.")
        }

        SwiftUI.Section {
          Toggle(isOn: onboardingToggleBinding) {
            VStack(alignment: .leading, spacing: 4) {
              Text("Introduction Flow")
                .font(.callout.weight(.semibold))
              Text("Run the guided tutorial when you enter a game.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .accessibilityIdentifier("onboarding-toggle")
        } header: {
          Text("Onboarding")
        } footer: {
          Text("Turn this on to rerun the introduction when entering a game.")
        }

        if AppEnvironment.allowsDeveloperSettings {
          SwiftUI.Section {
            Toggle(isOn: $useDevelopment) {
              VStack(alignment: .leading, spacing: 4) {
                Text("Developer server")
                  .font(.callout.weight(.semibold))
                Text("Use a custom development URL.")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            .accessibilityIdentifier("developer-server-toggle")

            if useDevelopment {
              TextField("Development URL", text: developerURLText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityIdentifier("developer-server-url-field")
              Text(developmentURLRaw)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Toggle(isOn: $showDebug) {
              VStack(alignment: .leading, spacing: 4) {
                Text("Debug mode")
                  .font(.callout.weight(.semibold))
                Text("Show debug UI")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            .accessibilityIdentifier("debug-toggle")
          } header: {
            Text("Developer")
          }
        }

        SwiftUI.Section {
          Text(appVersionText)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("settings-version-text")
        }
      }
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") {
            dismiss()
          }
          .accessibilityIdentifier("settings-done-button")
        }
      }
    }
  }
}
