import Foundation
import K86Kit
import Observation
import StatsCore

/// Shared state for the app: device connection, lighting, and statistics.
@MainActor
@Observable
final class AppModel {
  // Device
  var isConnected = false
  var firmware: String?
  var deviceError: String?

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
  var heatmap: [Int: Int] = [:]
  var statsError: String?
  var monitoringEnabled = false

  private var store: StatsStore?
  private var monitor: KeyMonitor?
  private var refreshTimer: Timer?

  // MARK: - Lifecycle

  func onAppear() {
    refreshDevice()
    openStore()
    refreshStats()
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.refreshDevice()
        self?.refreshStats()
      }
    }
  }

  func onDisappear() {
    refreshTimer?.invalidate()
    monitor?.stop()
    store?.close()
  }

  // MARK: - Device

  func refreshDevice() {
    isConnected = K86.isConnected
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
  private func withDevice(_ body: (K86) throws -> Void) {
    do {
      let keyboard = try K86()
      defer { keyboard.close() }
      try body(keyboard)
      deviceError = nil
    } catch {
      deviceError = String(describing: error)
      isConnected = false
    }
  }

  // MARK: - Lighting actions

  func applyMainLight() {
    withDevice { keyboard in
      try keyboard.setLEDs(on: true)
      if effect == .solid {
        try keyboard.setMainColor(
          mainColor.rgb, brightness: brightness, speed: speed)
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

  func uploadScreen(url: URL) {
    withDevice { keyboard in
      let frames = try Screen.loadFrames(url: url)
      if frames.count == 1 {
        try Screen.writeImage(frames[0], on: keyboard)
      } else {
        try Screen.writeAnimation(frames, on: keyboard)
      }
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
    guard let store, monitor == nil else { return }
    let monitor = KeyMonitor(store: store)
    do {
      try monitor.start()
      self.monitor = monitor
      monitoringEnabled = true
      statsError = nil
    } catch {
      statsError = String(describing: error)
      monitoringEnabled = false
    }
  }

  func stopMonitoring() {
    monitor?.stop()
    monitor = nil
    monitoringEnabled = false
    refreshStats()
  }

  func refreshStats() {
    guard let store else { return }
    do {
      try monitor?.flush()
      let todayKey = Self.dayString(Date())
      let monthStart = String(todayKey.prefix(7)) + "-01"
      let yearStart = String(todayKey.prefix(4)) + "-01-01"

      lifetimeTotal = try store.lifetimeTotal()
      today = try store.dayStat(todayKey)
      monthTotal = try store.total(from: monthStart, to: todayKey)
      yearTotal = try store.total(from: yearStart, to: todayKey)
      records = try store.records()
      monthChampions = try store.topKeys(from: monthStart, to: todayKey, limit: 10)
      heatmap = Dictionary(
        uniqueKeysWithValues: try store.topKeys(from: monthStart, to: todayKey, limit: 200)
          .map { ($0.keycode, $0.count) })
      statsError = nil
    } catch {
      statsError = String(describing: error)
    }
  }

  static func dayString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: date)
  }
}

/// Small RGB holder so views can bind without importing K86Kit types directly.
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
