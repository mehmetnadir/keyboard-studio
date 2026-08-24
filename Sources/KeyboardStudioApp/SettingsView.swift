import KeyboardKit
import StatsCore
import SwiftUI

struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @State private var language = AppLanguage.current
  @State private var languageChanged = false

  var body: some View {
    @Bindable var model = model

    Form {
      Section("settings.general") {
        Picker("menu.language", selection: $language) {
          ForEach(AppLanguage.allCases) { option in
            Text(option.label).tag(option)
          }
        }
        .onChange(of: language) { _, newValue in
          AppLanguage.apply(newValue)
          languageChanged = true
        }
        if languageChanged {
          Text("menu.language.restart_note")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section("settings.counting") {
        Toggle("settings.counting.enabled", isOn: countingBinding)
        Text("settings.counting.detail")
          .font(.caption)
          .foregroundStyle(.secondary)
        if model.pausedBySecureInput {
          Label("stats.secure_input.title", systemImage: "lock.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        LabeledContent("settings.data_location") {
          Button("settings.reveal") {
            NSWorkspace.shared.selectFile(
              StatsStore.defaultPath(), inFileViewerRootedAtPath: "")
          }
        }
      }

      Section("settings.device") {
        if let profile = model.profile {
          LabeledContent("settings.device.model", value: profile.displayName)
          LabeledContent("settings.device.id", value: profile.id)
          if let firmware = model.firmware {
            LabeledContent("settings.device.firmware", value: firmware)
          }
          if let screen = profile.capabilities.screen {
            LabeledContent(
              "settings.device.screen",
              value: "\(screen.width)×\(screen.height)"
                + (screen.verified ? "" : " " + "settings.device.unverified".localized))
          }
        } else {
          Text("device.disconnected")
            .foregroundStyle(.secondary)
        }
        LabeledContent("settings.device.add") {
          Button("settings.reveal") { revealDeviceFolder() }
        }
        Text("settings.device.add.detail")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("settings.about") {
        LabeledContent("settings.about.version", value: appVersion)
        Link("settings.about.source", destination: sourceURL)
        Text("settings.about.privacy")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  private var countingBinding: Binding<Bool> {
    Binding(
      get: { model.monitoringEnabled },
      set: { $0 ? model.startMonitoring() : model.stopMonitoring() })
  }

  private var appVersion: String {
    let info = Bundle.main.infoDictionary
    return (info?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
  }

  private var sourceURL: URL {
    URL(string: "https://github.com/mehmetnadir/keyboard-studio")!
  }

  /// Creates the folder if needed, so the user lands somewhere real.
  private func revealDeviceFolder() {
    let folder = DeviceCatalog.userDirectory
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    NSWorkspace.shared.open(folder)
  }
}
