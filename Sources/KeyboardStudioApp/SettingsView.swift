import KeyboardKit
import StatsCore
import SwiftUI

struct SettingsView: View {
  @State private var showCalibration = false
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
        if model.needsInputMonitoring {
          LabeledContent("settings.permission") {
            Button("stats.open_settings") { model.openInputMonitoringSettings() }
              .buttonStyle(.borderedProminent)
          }
        }
        LabeledContent("settings.data_location") {
          Button("settings.reveal") {
            NSWorkspace.shared.selectFile(
              StatsStore.defaultPath(), inFileViewerRootedAtPath: "")
          }
        }
      }

      Section("settings.app_rules") {
        appRulesSection
      }

      Section("settings.device") {
        if let profile = model.profile {
          LabeledContent("settings.device.model", value: profile.displayName)
          LabeledContent("settings.device.id", value: profile.id)
          if let firmware = model.firmware {
            LabeledContent("settings.device.firmware", value: firmware)
          }
          if let active = model.activeProfile {
            Picker("settings.device.profile", selection: profileBinding(active)) {
              ForEach(0..<3, id: \.self) { index in
                Text("settings.device.profile.n \(index + 1)").tag(index)
              }
            }
            Text("settings.device.profile.detail")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if profile.capabilities.screen != nil {
            screenSizeEditor
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

  /// Lighting that follows the frontmost app. Rules are made from whatever
  /// colour and effect are set right now, which is easier to reason about than
  /// a separate editor.
  @ViewBuilder private var appRulesSection: some View {
    @Bindable var model = model

    Toggle("settings.app_rules.enabled", isOn: $model.appRulesEnabled)
    Text("settings.app_rules.detail")
      .font(.caption)
      .foregroundStyle(.secondary)

    if model.appRulesEnabled {
      ForEach(model.appWatcher.rules) { rule in
        HStack(spacing: 10) {
          RoundedRectangle(cornerRadius: 5)
            .fill(Color(
              red: Double(rule.red) / 255, green: Double(rule.green) / 255,
              blue: Double(rule.blue) / 255))
            .frame(width: 22, height: 18)
          Text(rule.name)
          Text(rule.effect.rawValue.capitalized)
            .font(.caption)
            .foregroundStyle(.secondary)
          if model.activeAppRule?.id == rule.id {
            Text("settings.app_rules.active")
              .font(.caption2)
              .foregroundStyle(.tint)
          }
          Spacer()
          Button("settings.app_rules.remove") { model.removeAppRule(rule) }
            .buttonStyle(.link)
        }
      }

      Menu("settings.app_rules.add") {
        ForEach(AppProfileWatcher.runningApps(), id: \.bundleID) { app in
          Button(app.name) {
            model.addAppRule(bundleID: app.bundleID, name: app.name)
          }
        }
      }
      .frame(width: 220)
    }
  }

  /// The panel's resolution has to be established rather than assumed: the
  /// firmware reports ready for any frame size, so a size that "looks full"
  /// proves nothing. The wizard walks it in two clicks.
  @ViewBuilder private var screenSizeEditor: some View {
    @Bindable var model = model

    LabeledContent("settings.device.screen") {
      HStack(spacing: 6) {
        TextField("", text: $model.screenWidthText)
          .frame(width: 54)
          .multilineTextAlignment(.trailing)
        Text("×").foregroundStyle(.secondary)
        TextField("", text: $model.screenHeightText)
          .frame(width: 54)
        if model.profile?.capabilities.screen?.verified == false {
          Text("settings.device.unverified")
            .font(.caption2)
            .foregroundStyle(.orange)
        }
      }
      .textFieldStyle(.roundedBorder)
      .labelsHidden()
    }

    HStack(spacing: 10) {
      Menu("settings.screen.presets") {
        ForEach(Self.commonSizes, id: \.label) { size in
          Button(size.label) {
            model.screenWidthText = String(size.width)
            model.screenHeightText = String(size.height)
          }
        }
      }
      .frame(width: 150)
      Button("settings.screen.calibrate") { showCalibration = true }
        .disabled(!model.isConnected || model.isUploading)
      Button("settings.screen.test") {
        Task { await model.testScreenSize() }
      }
      .disabled(!model.isConnected || model.isUploading)
      Button("settings.screen.save") { model.saveScreenSize() }
        .disabled(model.profile == nil)
      if model.isUploading { ProgressView().controlSize(.small) }
    }

    if let message = model.screenSaveMessage {
      Text(message).font(.caption).foregroundStyle(.secondary)
    }
    Text("settings.screen.detail")
      .font(.caption)
      .foregroundStyle(.tertiary)
      .sheet(isPresented: $showCalibration) {
        CalibrationSheet().environment(model)
      }
  }

  /// Panel sizes seen across this protocol family.
  private static let commonSizes: [(label: String, width: Int, height: Int)] = [
    ("128 × 128", 128, 128), ("240 × 135", 240, 135), ("240 × 240", 240, 240),
    ("160 × 80", 160, 80), ("320 × 172", 320, 172), ("128 × 160", 128, 160),
  ]

  private func profileBinding(_ active: Int) -> Binding<Int> {
    Binding(get: { active }, set: { model.selectProfile($0) })
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
