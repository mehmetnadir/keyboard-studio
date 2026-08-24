import AppKit
import Foundation
import KeyboardKit

/// Lighting that changes with whatever app you are using.
///
/// Nothing in the protocol blocks this: macOS reports the frontmost app, and
/// we can already set a colour. Rules are stored as data so they survive
/// restarts and can be edited without touching code.
struct AppLightingRule: Codable, Identifiable, Hashable {
  var id: String { bundleID }
  /// Bundle identifier, e.g. "com.apple.dt.Xcode".
  var bundleID: String
  /// Shown in the list; the app's own name at the time the rule was made.
  var name: String
  var red: Int
  var green: Int
  var blue: Int
  var effectID: String

  var rgb: RGB {
    RGB(UInt8(clamping: red), UInt8(clamping: green), UInt8(clamping: blue))
  }

  var effect: LightEffect {
    LightEffect(rawValue: effectID) ?? .solid
  }

  init(bundleID: String, name: String, rgb: RGB, effect: LightEffect) {
    self.bundleID = bundleID
    self.name = name
    self.red = Int(rgb.r)
    self.green = Int(rgb.g)
    self.blue = Int(rgb.b)
    self.effectID = effect.rawValue
  }
}

/// Watches which app is in front and reports rule changes.
///
/// Deliberately edge-triggered: it only fires when the matching rule actually
/// changes, so alt-tabbing between two apps with no rules sends nothing to the
/// keyboard. Lighting commands are rate-limited by the firmware, and a naive
/// implementation would hammer them.
@MainActor
final class AppProfileWatcher {
  private(set) var rules: [AppLightingRule] = []
  private var observer: (any NSObjectProtocol)?
  private var lastAppliedRuleID: String?
  private var onChange: ((AppLightingRule?) -> Void)?

  private static let storageKey = "appLightingRules"

  init() {
    load()
  }

  func start(onChange: @escaping (AppLightingRule?) -> Void) {
    self.onChange = onChange
    guard observer == nil else { return }
    observer = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] note in
      // Pull the id out here: the notification itself is not Sendable, but a
      // String is, so nothing non-Sendable crosses into the actor hop.
      let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey]
        as? NSRunningApplication)?.bundleIdentifier
      MainActor.assumeIsolated {
        self?.frontmostChanged(to: bundleID)
      }
    }
    frontmostChanged(to: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
  }

  func stop() {
    if let observer {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      self.observer = nil
    }
    lastAppliedRuleID = nil
  }

  private func frontmostChanged(to bundleID: String?) {
    let match = bundleID.flatMap { id in rules.first { $0.bundleID == id } }
    // Only act on a real change — see the note about rate limits above.
    guard match?.id != lastAppliedRuleID else { return }
    lastAppliedRuleID = match?.id
    onChange?(match)
  }

  // MARK: - Rules

  func add(_ rule: AppLightingRule) {
    rules.removeAll { $0.bundleID == rule.bundleID }
    rules.append(rule)
    rules.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    save()
    // Re-evaluate: the rule may apply to the app in front right now.
    lastAppliedRuleID = nil
    frontmostChanged(to: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
  }

  func remove(_ rule: AppLightingRule) {
    rules.removeAll { $0.bundleID == rule.bundleID }
    save()
  }

  /// Apps currently running, as candidates for a new rule.
  static func runningApps() -> [(name: String, bundleID: String)] {
    NSWorkspace.shared.runningApplications
      .filter { $0.activationPolicy == .regular }
      .compactMap { app in
        guard let name = app.localizedName, let bundle = app.bundleIdentifier else { return nil }
        return (name, bundle)
      }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private func load() {
    guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
      let decoded = try? JSONDecoder().decode([AppLightingRule].self, from: data)
    else { return }
    rules = decoded
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(rules) else { return }
    UserDefaults.standard.set(data, forKey: Self.storageKey)
  }
}
