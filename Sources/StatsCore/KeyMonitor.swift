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
///
/// `onPress` is the one exception worth knowing about: it fires per press, in
/// order, for live UI. It carries a usage id and no timing, the app never sets
/// it, and it is off unless a caller opts in via `init(enableLiveCallback:)`.
public final class KeyMonitor {
  /// Emitted for live UI (heatmaps); carries a usage id, never a character.
  public typealias PressHandler = @Sendable (Int) -> Void

  private let vendorID: Int
  private let productID: Int
  private let store: StatsStore
  private let enableLiveCallback: Bool

  /// Guards the pending aggregates.
  private let lock = NSLock()
  /// Guards start/stop lifecycle fields, which are touched from the app, the
  /// timer queue, and the HID callback thread.
  private let stateLock = NSLock()
  private let queue = DispatchQueue(label: "dev.keyboardstudio.keymonitor")

  private var manager: IOHIDManager?
  private var timer: DispatchSourceTimer?
  private var selfReference: Unmanaged<KeyMonitor>?
  private var running = false
  private var matchedDevices = 0

  // Aggregates pending flush — reset on every successful write.
  private var counts: [Int: Int] = [:]
  private var hourBuckets: [Int: Int] = [:]
  private var pendingDay: String = KeyMonitor.today()
  private var activeMinutes = 0
  private var lastActiveMinute: Int?
  /// Batches whose write failed and that belong to a day already rolled past.
  private var carryOver: [Batch] = []

  private var pressHandler: PressHandler?
  private var flushErrorHandler: (@Sendable (Error) -> Void)?

  public init(
    store: StatsStore, vendorID: Int = 0x3151, productID: Int = 0x4015,
    enableLiveCallback: Bool = false
  ) {
    self.store = store
    self.vendorID = vendorID
    self.productID = productID
    self.enableLiveCallback = enableLiveCallback
  }

  deinit {
    // stop() must run on the owner's thread while the run loop is alive; a
    // late teardown here could race an in-flight callback.
    precondition(!running, "call stop() before releasing KeyMonitor")
  }

  // MARK: - Handlers

  /// Per-press callback for live UI. Ignored unless the monitor was created
  /// with `enableLiveCallback: true`. Set it before `start()`.
  public var onPress: PressHandler? {
    get { stateLock.withLock { pressHandler } }
    set { stateLock.withLock { pressHandler = newValue } }
  }

  /// Called when a flush fails, so the UI can tell the user counting stopped
  /// persisting instead of failing silently.
  public var onFlushError: (@Sendable (Error) -> Void)? {
    get { stateLock.withLock { flushErrorHandler } }
    set { stateLock.withLock { flushErrorHandler = newValue } }
  }

  public var isRunning: Bool {
    stateLock.withLock { running }
  }

  /// How many K86 keyboards the HID manager currently sees. Zero means nothing
  /// will ever be counted — surface it rather than showing an eternal 0.
  public var matchedDeviceCount: Int {
    stateLock.withLock { matchedDevices }
  }

  // MARK: - Lifecycle

  /// Starts counting. Triggers the system's Input Monitoring prompt on first run.
  ///
  /// - Throws: `MonitorError` if the HID manager cannot be opened — most often
  ///   because Input Monitoring permission was denied.
  public func start(flushInterval: TimeInterval = 60) throws {
    stateLock.lock()
    guard !running else {
      stateLock.unlock()
      return
    }
    stateLock.unlock()

    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matching: [String: Any] = [
      kIOHIDVendorIDKey: vendorID,
      kIOHIDProductIDKey: productID,
      kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
      kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
    ]
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

    // Retained for the lifetime of the registration: the run loop holds only a
    // raw pointer, so the object must not be freed while callbacks can fire.
    let reference = Unmanaged.passRetained(self)
    let context = reference.toOpaque()
    IOHIDManagerRegisterInputValueCallback(manager, keyMonitorInputCallback, context)
    IOHIDManagerRegisterDeviceMatchingCallback(manager, keyMonitorDeviceAdded, context)
    IOHIDManagerRegisterDeviceRemovalCallback(manager, keyMonitorDeviceRemoved, context)
    IOHIDManagerScheduleWithRunLoop(
      manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

    let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard result == kIOReturnSuccess else {
      IOHIDManagerUnscheduleFromRunLoop(
        manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
      reference.release()
      throw MonitorError.inputMonitoringDenied(result)
    }

    let devices = (IOHIDManagerCopyDevices(manager) as? Set<AnyHashable>)?.count ?? 0
    stateLock.withLock {
      self.manager = manager
      self.selfReference = reference
      self.running = true
      self.matchedDevices = devices
    }
    startTimer(interval: flushInterval)
  }

  public func stop() {
    stateLock.lock()
    guard running else {
      stateLock.unlock()
      return
    }
    let manager = self.manager
    let reference = self.selfReference
    let timer = self.timer
    self.manager = nil
    self.selfReference = nil
    self.timer = nil
    running = false
    matchedDevices = 0
    stateLock.unlock()

    timer?.cancel()
    if let manager {
      IOHIDManagerUnscheduleFromRunLoop(
        manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
      IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }
    do {
      try flush()
    } catch {
      reportFlushError(error)
    }
    reference?.release()
  }

  private func startTimer(interval: TimeInterval) {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + interval, repeating: interval)
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      do {
        try flush()
      } catch {
        reportFlushError(error)
      }
    }
    timer.resume()
    stateLock.withLock { self.timer = timer }
  }

  private func reportFlushError(_ error: Error) {
    stateLock.withLock { flushErrorHandler }?(error)
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
    var finished: Batch?
    if day != pendingDay {
      finished = drainLocked()
      pendingDay = day
      lastActiveMinute = nil
    }
    counts[usage, default: 0] += 1
    hourBuckets[hour, default: 0] += 1
    if lastActiveMinute != minute {
      lastActiveMinute = minute
      activeMinutes += 1
    }
    lock.unlock()

    if let finished {
      // The finished day is queued rather than written here: an SQLite write on
      // the input thread would stall key delivery. It lands on the next flush,
      // or sooner via this async nudge.
      lock.lock()
      carryOver.append(finished)
      lock.unlock()
      queue.async { [weak self] in
        guard let self else { return }
        do {
          try flush()
        } catch {
          reportFlushError(error)
        }
      }
    }

    if enableLiveCallback {
      stateLock.withLock { pressHandler }?(usage)
    }
  }

  /// Writes pending aggregates to the store and clears them.
  public func flush() throws {
    lock.lock()
    let pending = carryOver
    carryOver.removeAll(keepingCapacity: false)
    let batch = drainLocked()
    lock.unlock()

    var firstError: Error?
    for old in pending {
      do {
        try write(old)
      } catch {
        firstError = firstError ?? error
      }
    }
    do {
      try write(batch)
    } catch {
      firstError = firstError ?? error
    }
    if let firstError { throw firstError }
  }

  struct Batch {
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
      lock.lock()
      if batch.day == pendingDay {
        // Same day still open: fold the counts back into the live totals.
        for (key, value) in batch.counts { counts[key, default: 0] += value }
        for (key, value) in batch.hourBuckets { hourBuckets[key, default: 0] += value }
        activeMinutes += batch.activeMinutes
      } else {
        // A past day must keep its own date — never merge it into today.
        carryOver.append(batch)
      }
      lock.unlock()
      throw error
    }
  }

  // MARK: - Dates

  /// One shared zone for both the calendar and the formatter, so the day string
  /// and the hour bucket can never disagree.
  static let timeZone = TimeZone.autoupdatingCurrent

  static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }()

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    return formatter
  }()

  public static func dayString(_ date: Date) -> String {
    dayFormatter.string(from: date)
  }

  public static func today() -> String {
    dayString(Date())
  }
}

// MARK: - C callbacks

/// Resolves the element's usage page/id and counts it.
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

private func keyMonitorDeviceAdded(
  context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?,
  device: IOHIDDevice
) {
  guard let context else { return }
  Unmanaged<KeyMonitor>.fromOpaque(context).takeUnretainedValue().deviceCountChanged(by: 1)
}

private func keyMonitorDeviceRemoved(
  context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?,
  device: IOHIDDevice
) {
  guard let context else { return }
  Unmanaged<KeyMonitor>.fromOpaque(context).takeUnretainedValue().deviceCountChanged(by: -1)
}

extension KeyMonitor {
  fileprivate func deviceCountChanged(by delta: Int) {
    stateLock.withLock { matchedDevices = max(0, matchedDevices + delta) }
  }
}
