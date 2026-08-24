import Foundation
import IOKit.hid

/// Counts key presses on the Attack Shark K86 — and nothing else.
///
/// ## Privacy design
///
/// This is the one part of Keyboard Studio that touches keyboard input, so its
/// limits are deliberate and structural rather than a matter of policy:
///
/// - `IOHIDManagerSetDeviceMatching` binds the callback to a single device
///   (vendor 0x3151 / product 0x4015). Other keyboards, including the built-in
///   one, never reach this process. `CGEventTap` cannot make that distinction,
///   which is why it is not used here.
/// - Only usage page 0x07 (Keyboard/Keypad) values are counted; consumer keys,
///   the knob and mouse-like usages are ignored.
/// - Presses accumulate into two dictionaries: keycode → count and hour → count.
///   The order of presses is never recorded, so nothing here can reconstruct
///   typed text. There is no buffer to leak.
/// - Nothing is written anywhere until `flush()` hands the aggregates to
///   `StatsStore`.
public final class KeyMonitor {
  /// Emitted for live UI (heatmaps); carries a usage id, never a character.
  public typealias PressHandler = @Sendable (Int) -> Void

  private let vendorID: Int
  private let productID: Int
  private let store: StatsStore
  private let lock = NSLock()

  private var manager: IOHIDManager?
  private var timer: DispatchSourceTimer?
  private let queue = DispatchQueue(label: "dev.keyboardstudio.keymonitor")

  // Aggregates pending flush — reset on every successful write.
  private var counts: [Int: Int] = [:]
  private var hourBuckets: [Int: Int] = [:]
  private var pendingDay: String = KeyMonitor.today()
  private var activeMinutes = 0
  private var lastActiveMinute: Int?

  public var onPress: PressHandler?
  public private(set) var isRunning = false

  public init(store: StatsStore, vendorID: Int = 0x3151, productID: Int = 0x4015) {
    self.store = store
    self.vendorID = vendorID
    self.productID = productID
  }

  deinit {
    stop()
  }

  // MARK: - Lifecycle

  /// Starts counting. Triggers the system's Input Monitoring prompt on first run.
  ///
  /// - Throws: `MonitorError` if the HID manager cannot be opened — most often
  ///   because Input Monitoring permission was denied.
  public func start(flushInterval: TimeInterval = 60) throws {
    guard !isRunning else { return }

    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matching: [String: Any] = [
      kIOHIDVendorIDKey: vendorID,
      kIOHIDProductIDKey: productID,
      kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
      kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
    ]
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

    let context = Unmanaged.passUnretained(self).toOpaque()
    IOHIDManagerRegisterInputValueCallback(manager, keyMonitorInputCallback, context)
    IOHIDManagerScheduleWithRunLoop(
      manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

    let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard result == kIOReturnSuccess else {
      IOHIDManagerUnscheduleFromRunLoop(
        manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
      throw MonitorError.inputMonitoringDenied(result)
    }

    self.manager = manager
    isRunning = true
    startTimer(interval: flushInterval)
  }

  public func stop() {
    timer?.cancel()
    timer = nil
    if let manager {
      IOHIDManagerUnscheduleFromRunLoop(
        manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
      IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
      self.manager = nil
    }
    isRunning = false
    try? flush()
  }

  private func startTimer(interval: TimeInterval) {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + interval, repeating: interval)
    timer.setEventHandler { [weak self] in
      try? self?.flush()
    }
    timer.resume()
    self.timer = timer
  }

  // MARK: - Counting

  /// Records one press. Called from the HID callback; keep it allocation-light.
  func record(usage: Int, at date: Date = Date()) {
    let day = Self.dayString(date)
    let hour = Self.calendar.component(.hour, from: date)
    // Minute-of-epoch is compared and discarded — a minute counts as active if
    // it saw at least one press. The minutes themselves are never stored.
    let minute = Int(date.timeIntervalSince1970 / 60)

    lock.lock()
    if day != pendingDay {
      // Crossing midnight: persist the finished day before switching.
      let finished = drainLocked()
      lock.unlock()
      try? write(finished)
      lock.lock()
      pendingDay = day
    }
    counts[usage, default: 0] += 1
    hourBuckets[hour, default: 0] += 1
    if lastActiveMinute != minute {
      lastActiveMinute = minute
      activeMinutes += 1
    }
    lock.unlock()

    onPress?(usage)
  }

  /// Writes pending aggregates to the store and clears them.
  public func flush() throws {
    lock.lock()
    let batch = drainLocked()
    lock.unlock()
    try write(batch)
  }

  private struct Batch {
    let day: String
    let counts: [Int: Int]
    let hourBuckets: [Int: Int]
    let activeMinutes: Int
    var isEmpty: Bool { counts.isEmpty && activeMinutes == 0 }
  }

  /// Caller must hold `lock`.
  private func drainLocked() -> Batch {
    let batch = Batch(
      day: pendingDay, counts: counts, hourBuckets: hourBuckets, activeMinutes: activeMinutes)
    counts.removeAll(keepingCapacity: true)
    hourBuckets.removeAll(keepingCapacity: true)
    activeMinutes = 0
    return batch
  }

  private func write(_ batch: Batch) throws {
    guard !batch.isEmpty else { return }
    do {
      try store.flush(
        day: batch.day, counts: batch.counts, hourBuckets: batch.hourBuckets,
        activeMinutes: batch.activeMinutes)
    } catch {
      // Put the counts back so a transient DB error doesn't lose the day's data.
      lock.lock()
      for (key, value) in batch.counts { counts[key, default: 0] += value }
      for (key, value) in batch.hourBuckets { hourBuckets[key, default: 0] += value }
      activeMinutes += batch.activeMinutes
      lock.unlock()
      throw error
    }
  }

  // MARK: - Dates

  static let calendar = Calendar(identifier: .gregorian)

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
  }()

  static func dayString(_ date: Date) -> String {
    dayFormatter.string(from: date)
  }

  static func today() -> String {
    dayString(Date())
  }
}

/// C callback trampoline — resolves the element's usage page/id and counts it.
private func keyMonitorInputCallback(
  context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?,
  value: IOHIDValue
) {
  guard let context, result == kIOReturnSuccess else { return }
  let element = IOHIDValueGetElement(value)
  // Key-down only (1); key-up is 0 and would double every count.
  guard IOHIDValueGetIntegerValue(value) == 1,
    IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_KeyboardOrKeypad)
  else { return }

  let usage = Int(IOHIDElementGetUsage(element))
  // 0..3 are error/reserved usages the firmware emits during roll-over.
  guard usage > 3 else { return }

  let monitor = Unmanaged<KeyMonitor>.fromOpaque(context).takeUnretainedValue()
  monitor.record(usage: usage)
}
