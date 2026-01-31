import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var themeSelectionRaw: String
  @Binding var serverEnvironmentRaw: String
  @AppStorage("debug.enabled") private var showDebug = false

  private var selection: ThemeSelection {
    ThemeSelection(rawValue: themeSelectionRaw) ?? .system
  }

  var body: some View {
    let selectionBinding = Binding<ThemeSelection>(
      get: { ThemeSelection(rawValue: themeSelectionRaw) ?? .system },
      set: { themeSelectionRaw = $0.rawValue }
    )
    let serverEnvironmentBinding = Binding<ServerEnvironment>(
      get: { AppEnvironment.serverEnvironment(from: serverEnvironmentRaw) },
      set: { serverEnvironmentRaw = $0.rawValue }
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
          SwiftUI.Picker("Server", selection: serverEnvironmentBinding) {
            ForEach(ServerEnvironment.allCases) { environment in
              VStack(alignment: .leading, spacing: 4) {
                Text(environment.title)
                Text(environment.detail)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              .tag(environment)
            }
          }
          .pickerStyle(.inline)
          .accessibilityIdentifier("server-picker")

          Text(AppEnvironment.serverEnvironment(from: serverEnvironmentRaw).baseURL.absoluteString)
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
          Text("Server")
        } footer: {
          Text("Switching servers signs you out and reloads games.")
        }

        SwiftUI.Section {
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
