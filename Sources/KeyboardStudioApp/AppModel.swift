import Foundation
import KeyboardKit
import Observation
import StatsCore
import StatsScreen
import SwiftUI

/// Shared state for the app: device connection, lighting, and statistics.
@MainActor
@Observable
final class AppModel {
  // Device
  var isConnected = false
  var firmware: String?
  var deviceError: String?
  var isUploading = false
  /// Which keyboard model is attached, and how it is drawn. Both come from the
  /// device catalogue, so a new board needs no code here.
  var profile: DeviceProfile?
  var layout: KeyboardLayout?

  // Lighting (mirrors what the user last applied; the keyboard has no read-back
  // for the active colour, so this is intent, not device truth)
  var mainColor = Color3(155, 89, 182)
  var sideColor = Color3(0, 220, 220)
  var effect: LightEffect = .solid
  var brightness = 4
  var speed = 3
  var rainbow = false

  // Statistics
  var lifetimeTotal = 0
  var today: DayStat?
  var monthTotal = 0
  var yearTotal = 0
  var records: Records?
  var monthChampions: [KeyStat] = []
  var statsError: String?
  var monitoringEnabled = false
  /// True when counting is on but no K86 is visible to the HID manager, which
  /// would otherwise look like "counting works, you just never type".
  var keyboardNotDetected = false
  /// macOS is protecting keyboard input right now (a password field is
  /// focused), so nothing is being counted.
  var pausedBySecureInput = false

  // Knob
  var knobSlots: Knob.SlotMap?
  var knobBindings: [Knob.Action: Knob.Binding] = [:]
  var knobError: String?

  /// Mirrors today's card onto the keyboard screen while the app runs.
  var screenShowsStats = false {
    didSet { screenShowsStats ? startScreenMirror() : stopScreenMirror() }
  }
  var screenStatus: String?

  private var store: StatsStore?
  private var monitor: KeyMonitor?
  private var refreshTimer: Timer?
  private var screenTimer: Timer?
  private var terminationObserver: (any NSObjectProtocol)?
  private var wakeObserver: (any NSObjectProtocol)?

  private static let monitoringPreferenceKey = "counting.enabled"

  // MARK: - Lifecycle

  func onAppear() {
    guard store == nil else {
      // SwiftUI can re-run onAppear without a matching onDisappear.
      refreshDevice()
      refreshStats()
      return
    }
    openStore()
    refreshDevice()
    refreshStats()

    refreshTimer?.invalidate()
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refreshDevice()
        self?.refreshStats()
      }
    }

    // Teardown belongs to the app, not the window: closing the window of a
    // menu-bar app must not stop counting.
    if terminationObserver == nil {
      terminationObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.shutDown() }
      }
    }

    // USB devices re-enumerate across sleep, which leaves a long-lived HID
    // manager attached to a device that no longer exists. Restart counting and
    // re-detect the keyboard on wake rather than silently counting nothing.
    if wakeObserver == nil {
      wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.handleWake() }
      }
    }

    if UserDefaults.standard.bool(forKey: Self.monitoringPreferenceKey) {
      startMonitoring()
    }
  }

  private func handleWake() {
    refreshDevice()
    guard monitoringEnabled else {
      refreshStats()
      return
    }
    // Flushes pending counts, then rebinds to the re-enumerated device.
    monitor?.stop()
    monitor = nil
    monitoringEnabled = false
    startMonitoring()
    refreshStats()
  }

  /// Flushes and releases everything. Safe to call more than once.
  func shutDown() {
    refreshTimer?.invalidate()
    refreshTimer = nil
    screenTimer?.invalidate()
    screenTimer = nil
    monitor?.stop()
    monitor = nil
    monitoringEnabled = false
    store?.close()
    store = nil
    if let terminationObserver {
      NotificationCenter.default.removeObserver(terminationObserver)
      self.terminationObserver = nil
    }
    if let wakeObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
      self.wakeObserver = nil
    }
  }

  // MARK: - Device

  func refreshDevice() {
    let connected = DeviceCatalog.firstConnected()
    isConnected = connected != nil
    if profile?.id != connected?.id {
      profile = connected
      layout = connected?.layout.flatMap(KeyboardLayout.load(named:))
      knobSlots = nil
      knobBindings = [:]
    }
    guard isConnected else {
      firmware = nil
      return
    }
    withDevice { keyboard in
      if let version = try keyboard.firmwareVersion() {
        firmware = String(format: "0x%04x", version)
      }
    }
  }

  /// Runs a device operation, surfacing failures instead of swallowing them.
  private func withDevice(_ body: (Keyboard) throws -> Void) {
    do {
      let keyboard = try Keyboard()
      defer { keyboard.close() }
      try body(keyboard)
      deviceError = nil
    } catch {
      deviceError = String(describing: error)
      isConnected = false
    }
  }

  // MARK: - Knob

  /// Finds the knob's slots on the connected board and reads its bindings.
  ///
  /// Slot positions are discovered rather than assumed — they differ between
  /// models that share this protocol.
  func loadKnob() {
    guard isConnected, knobSlots == nil else { return }
    withDevice { keyboard in
      guard try keyboard.verifyIdentity() else {
        knobError = "knob.identity_mismatch".localized
        return
      }
      guard let slots = try Keymap.discoverKnobSlots(on: keyboard) else {
        knobError = nil
        return
      }
      knobSlots = slots
      knobBindings = try Keymap.readKnob(slots, on: keyboard)
      knobError = nil
    }
  }

  /// Changing a binding is not wired to the device yet: the keymap *write*
  /// command has not been confirmed on hardware, and writing a wrong slot
  /// remaps a real key. The picker updates what is shown; applying it comes
  /// once the write path is verified.
  func setKnob(action: Knob.Action, mediaCode: Int?) {
    knobBindings[action] = mediaCode.map { Knob.Binding.media(code: $0) } ?? .unassigned
    knobError = "knob.write_pending".localized
  }

  // MARK: - Lighting actions

  func applyMainLight() {
    withDevice { keyboard in
      try keyboard.setLEDs(on: true)
      if effect == .solid {
        try keyboard.setMainColor(mainColor.rgb, brightness: brightness, speed: speed)
      } else {
        try keyboard.setMainEffect(
          effect, brightness: brightness, speed: speed,
          rainbow: rainbow, color: mainColor.rgb)
      }
    }
  }

  func applySideLight() {
    withDevice { keyboard in
      try keyboard.setLEDs(on: true)
      try keyboard.setSideColor(sideColor.rgb, brightness: brightness, speed: speed)
    }
  }

  func setLEDs(on: Bool) {
    withDevice { keyboard in
      try keyboard.setLEDs(on: on)
    }
  }

  /// Uploads off the main thread: a 30-frame GIF takes roughly 20 seconds of
  /// chunked writes, which would otherwise freeze the whole UI.
  func uploadScreen(url: URL, mode: KeyboardKit.ContentMode = .fill) async {
    isUploading = true
    defer { isUploading = false }
    do {
      try await Task.detached(priority: .userInitiated) {
        let keyboard = try Keyboard()
        defer { keyboard.close() }
        let frames = try Screen.loadFrames(url: url, for: keyboard, mode: mode)
        if frames.count == 1 {
          try Screen.writeImage(frames[0], on: keyboard)
        } else {
          try Screen.writeAnimation(frames, on: keyboard)
        }
      }.value
      deviceError = nil
    } catch {
      deviceError = String(describing: error)
    }
  }

  // MARK: - Screen mirror

  private func startScreenMirror() {
    Task { await pushStatsToScreen() }
    screenTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.pushStatsToScreen() }
    }
  }

  private func stopScreenMirror() {
    screenTimer?.invalidate()
    screenTimer = nil
    screenStatus = nil
  }

  func pushStatsToScreen() async {
    guard let store, isConnected else {
      screenStatus = "screen.connect_to_update".localized
      return
    }
    do {
      try monitor?.flush()
      let card = try StatsCard.today(store: store)
      try await Task.detached(priority: .utility) {
        let keyboard = try Keyboard()
        defer { keyboard.close() }
        try Screen.writeImage(card, on: keyboard)
      }.value
      screenStatus = "screen.updated".localized(
        Date().formatted(date: .omitted, time: .shortened))
    } catch {
      screenStatus = String(describing: error)
    }
  }

  // MARK: - Statistics

  private func openStore() {
    do {
      store = try StatsStore(path: StatsStore.defaultPath())
    } catch {
      statsError = String(describing: error)
    }
  }

  func startMonitoring() {
    guard let store else { return }
    guard monitor == nil else {
      monitoringEnabled = monitor?.isRunning ?? false
      return
    }
    let monitor = KeyMonitor(store: store)
    monitor.onFlushError = { [weak self] error in
      Task { @MainActor in self?.statsError = String(describing: error) }
    }
    do {
      try monitor.start()
      self.monitor = monitor
      monitoringEnabled = true
      keyboardNotDetected = monitor.matchedDeviceCount == 0
      statsError = nil
      UserDefaults.standard.set(true, forKey: Self.monitoringPreferenceKey)
    } catch {
      statsError = String(describing: error)
      monitoringEnabled = false
    }
  }

  func stopMonitoring() {
    monitor?.stop()
    monitor = nil
    monitoringEnabled = false
    keyboardNotDetected = false
    UserDefaults.standard.set(false, forKey: Self.monitoringPreferenceKey)
    refreshStats()
  }

  func refreshStats() {
    guard let store else { return }
    do {
      try monitor?.flush()
      keyboardNotDetected = monitoringEnabled && (monitor?.matchedDeviceCount ?? 0) == 0
      pausedBySecureInput = monitoringEnabled && SecureInput.isActive

      let todayKey = KeyMonitor.today()
      let monthStart = String(todayKey.prefix(7)) + "-01"
      let yearStart = String(todayKey.prefix(4)) + "-01-01"

      lifetimeTotal = try store.lifetimeTotal()
      today = try store.dayStat(todayKey)
      monthTotal = try store.total(from: monthStart, to: todayKey)
      yearTotal = try store.total(from: yearStart, to: todayKey)
      records = try store.records()
      monthChampions = try store.topKeys(from: monthStart, to: todayKey, limit: 10)
      statsError = nil
    } catch {
      statsError = String(describing: error)
    }
  }
}

/// Small RGB holder so views can bind without importing KeyboardKit types directly.
struct Color3: Equatable {
  var r: Double
  var g: Double
  var b: Double

  init(_ r: Int, _ g: Int, _ b: Int) {
    self.r = Double(r) / 255
    self.g = Double(g) / 255
    self.b = Double(b) / 255
  }

  var rgb: RGB {
    RGB(
      UInt8(max(0, min(255, r * 255))), UInt8(max(0, min(255, g * 255))),
      UInt8(max(0, min(255, b * 255))))
  }
}
