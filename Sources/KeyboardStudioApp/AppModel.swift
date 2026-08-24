import Foundation
import KeyboardKit
import Observation
import StatsCore
import NowPlaying
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
  /// Set when counting failed specifically because Input Monitoring is not
  /// granted — the one error the user can fix from here.
  var needsInputMonitoring = false
  var monitoringEnabled = false
  /// True when counting is on but no K86 is visible to the HID manager, which
  /// would otherwise look like "counting works, you just never type".
  var keyboardNotDetected = false
  /// macOS is protecting keyboard input right now (a password field is
  /// focused), so nothing is being counted.
  var pausedBySecureInput = false

  // Screen geometry the user can correct when detection is not possible
  var screenWidthText = ""
  var screenHeightText = ""
  var screenSaveMessage: String?

  // Keymap / shortcuts
  /// Pending shortcut assignments, keyed by layout key id. Held in the app
  /// until the keymap write path is verified on hardware.
  var pendingShortcuts: [String: Shortcut] = [:]
  var keymapLoaded = false

  // Knob
  var knobSlots: Knob.SlotMap?
  var knobBindings: [Knob.Action: Knob.Binding] = [:]
  var knobError: String?

  /// What the keyboard screen is showing while the app runs.
  var screenMode: ScreenMode = .off {
    didSet { screenModeChanged() }
  }
  var screenStatus: String?
  var nowPlaying: NowPlaying?
  /// Tie the lighting to the track as well as the screen.
  var lightFollowsMusic = false {
    didSet {
      if lightFollowsMusic { Task { await syncLightToMusic() } }
    }
  }

  enum ScreenMode: String, CaseIterable, Identifiable {
    case off, stats, nowPlaying
    var id: String { rawValue }
  }

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
      if let screen = connected?.capabilities.screen {
        screenWidthText = String(screen.width)
        screenHeightText = String(screen.height)
      }
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

  // MARK: - Shortcuts

  /// Reads the board's current keymap so assigned keys can be shown.
  func loadKeymap() {
    guard isConnected, !keymapLoaded else { return }
    keymapLoaded = true
    // Reading is safe and already verified; writing is not enabled yet.
    withDevice { keyboard in
      _ = try Keymap.readPage(0, on: keyboard)
    }
  }

  func assignShortcut(_ shortcut: Shortcut, toKeyIDs ids: Set<String>, in layout: KeyboardLayout) {
    for id in ids where layout.keys.contains(where: { $0.id == id }) {
      pendingShortcuts[id] = shortcut
    }
  }

  func assignedShortcutLabel(for key: KeyboardLayout.Key) -> String? {
    guard let shortcut = pendingShortcuts[key.id] else { return nil }
    return shortcut.modifiers.symbols + KeyLabels.name(for: shortcut.usage)
  }

  // MARK: - Screen geometry

  /// Sends a calibration pattern at the entered size so the user can see
  /// whether it fits the panel. Nothing is saved by this.
  func testScreenSize() async {
    guard let size = enteredScreenSize else {
      screenSaveMessage = "screen.size.invalid".localized
      return
    }
    isUploading = true
    defer { isUploading = false }
    do {
      try await Task.detached(priority: .userInitiated) {
        let keyboard = try Keyboard()
        defer { keyboard.close() }
        let frame = Screen.bandPattern(width: size.width, height: size.height)
        try Screen.writeImage(frame, on: keyboard)
      }.value
      screenSaveMessage = "screen.size.tested".localized
    } catch {
      screenSaveMessage = String(describing: error)
    }
  }

  /// Records the size the user confirmed, marking it verified — a human looked
  /// at the panel, which is the only evidence this protocol allows.
  func saveScreenSize() {
    guard var profile, let size = enteredScreenSize else {
      screenSaveMessage = "screen.size.invalid".localized
      return
    }
    var screen = profile.capabilities.screen
      ?? DeviceProfile.ScreenSpec(width: size.width, height: size.height)
    screen.width = size.width
    screen.height = size.height
    screen.verified = true
    profile.capabilities.screen = screen
    if DeviceCatalog.save(profile) {
      self.profile = profile
      screenSaveMessage = "screen.size.saved".localized
    } else {
      screenSaveMessage = "screen.size.save_failed".localized
    }
  }

  private var enteredScreenSize: (width: Int, height: Int)? {
    guard let width = Int(screenWidthText), let height = Int(screenHeightText),
      (8...512).contains(width), (8...512).contains(height)
    else { return nil }
    return (width, height)
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

  private func screenModeChanged() {
    screenTimer?.invalidate()
    screenTimer = nil
    guard screenMode != .off else {
      screenStatus = nil
      return
    }
    Task { await refreshScreen() }
    // Now playing changes often; statistics barely move within an hour.
    let interval: TimeInterval = screenMode == .nowPlaying ? 5 : 300
    screenTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
      [weak self] _ in
      Task { @MainActor in await self?.refreshScreen() }
    }
  }

  private func refreshScreen() async {
    switch screenMode {
    case .off: break
    case .stats: await pushStatsToScreen()
    case .nowPlaying: await pushNowPlayingToScreen()
    }
    if lightFollowsMusic { await syncLightToMusic() }
  }

  /// Gives the keyboard the track's colour.
  ///
  /// Updated at most every couple of seconds: lighting commands are
  /// rate-limited by the firmware, and pushing them faster wedges the control
  /// endpoint until the keyboard is re-plugged. A beat-synced strobe is not
  /// something this hardware can do.
  private var lastLightSync = Date.distantPast

  func syncLightToMusic() async {
    guard lightFollowsMusic, isConnected else { return }
    guard Date().timeIntervalSince(lastLightSync) >= MusicLight.updateInterval else { return }
    let playing = nowPlaying ?? PlayerBridge.current()
    guard let playing else { return }

    lastLightSync = Date()
    let color = MusicLight.color(
      for: playing, drift: MusicLight.drift(progress: playing.progress))
    mainColor = Color3(Int(color.r), Int(color.g), Int(color.b))
    effect = .solid
    applyMainLight()
  }

  /// Only uploads when the track actually changed — the panel write takes about
  /// a second, and re-sending the same frame every five seconds is wasteful.
  func pushNowPlayingToScreen() async {
    let playing = PlayerBridge.current()
    guard playing != nowPlaying else { return }
    nowPlaying = playing

    guard let playing else {
      screenStatus = "screen.nothing_playing".localized
      return
    }
    guard isConnected else {
      screenStatus = "screen.connect_to_update".localized
      return
    }
    let panel = profile?.capabilities.screen
    let card = NowPlayingCard.render(
      playing, width: panel?.width ?? Screen.width, height: panel?.height ?? Screen.height)
    do {
      try await Task.detached(priority: .utility) {
        let keyboard = try Keyboard()
        defer { keyboard.close() }
        try Screen.writeImage(card, on: keyboard)
      }.value
      screenStatus = "\(playing.title) — \(playing.artist)"
    } catch {
      screenStatus = String(describing: error)
    }
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
      needsInputMonitoring = false
      UserDefaults.standard.set(true, forKey: Self.monitoringPreferenceKey)
    } catch {
      statsError = String(describing: error)
      needsInputMonitoring = (error as? MonitorError)?.isPermissionDenied ?? false
      monitoringEnabled = false
    }
  }

  func openInputMonitoringSettings() {
    MonitorError.openInputMonitoringSettings()
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
