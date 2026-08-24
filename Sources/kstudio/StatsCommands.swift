import Foundation
import StatsCore

/// Press tally for the live `watch` display; the HID callback runs off-thread.
private final class LiveCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int {
    lock.withLock { count }
  }

  func increment() {
    lock.withLock { count += 1 }
  }
}

/// `kstudio stats` and `kstudio watch`.
enum StatsCommands {
  static func run(_ args: [String]) throws {
    let store = try StatsStore(path: StatsStore.defaultPath())
    defer { store.close() }

    switch args.first {
    case "watch":
      try watch(store: store, seconds: args.count > 1 ? Double(args[1]) ?? 30 : 30)
    default:
      try summary(store: store)
    }
  }

  // MARK: - Summary

  private static func summary(store: StatsStore) throws {
    let lifetime = try store.lifetimeTotal()
    guard lifetime > 0 else {
      print("No statistics yet. Run `kstudio watch` to start counting.")
      return
    }

    let today = day(Date())
    let records = try store.records()
    let monthStart = String(today.prefix(7)) + "-01"
    let yearStart = String(today.prefix(4)) + "-01-01"

    print("Keyboard Studio — typing statistics")
    print(String(repeating: "─", count: 42))
    print(row("Lifetime presses", format(lifetime)))
    if let todayStat = try store.dayStat(today) {
      print(row("Today", "\(format(todayStat.presses))  ·  \(todayStat.activeMinutes) active min"))
    } else {
      print(row("Today", "—"))
    }
    print(row("This month", format(try store.total(from: monthStart, to: today))))
    print(row("This year", format(try store.total(from: yearStart, to: today))))
    print(row("Current streak", "\(records.currentStreak) day\(records.currentStreak == 1 ? "" : "s")"))
    print(row("Longest streak", "\(records.longestStreak) days"))
    if let peak = records.peakHour {
      print(row("Peak hour", String(format: "%02d:00 – %02d:00", peak, (peak + 1) % 24)))
    }
    if let busiest = records.busiestDay {
      print(row("Busiest day", "\(busiest.day)  ·  \(format(busiest.presses))"))
    }

    let champions = try store.topKeys(from: monthStart, to: today, limit: 8)
    if !champions.isEmpty {
      print("\nThis month's champions")
      let max = champions.first?.count ?? 1
      for (index, stat) in champions.enumerated() {
        let bar = String(repeating: "▇", count: Swift.max(1, stat.count * 22 / Swift.max(max, 1)))
        let name = KeyNames.name(for: stat.keycode)
        print(String(format: "%2d. %-14@ %@ %@", index + 1, name as NSString, bar, format(stat.count)))
      }
    }
  }

  private static func row(_ label: String, _ value: String) -> String {
    label.padding(toLength: 18, withPad: " ", startingAt: 0) + value
  }

  private static func format(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
  }

  // MARK: - Watch

  private static func watch(store: StatsStore, seconds: Double) throws {
    let monitor = KeyMonitor(store: store, enableLiveCallback: true)
    let live = LiveCounter()
    monitor.onPress = { _ in live.increment() }
    monitor.onFlushError = { error in
      errPrint("warning: could not save counts — \(error)")
    }

    do {
      try monitor.start(flushInterval: 10)
    } catch {
      errPrint("error: \(error)")
      errPrint(
        """

        Grant permission: System Settings → Privacy & Security → Input Monitoring,
        then add this binary:
          \(CommandLine.arguments[0])
        """)
      exit(1)
    }

    if monitor.matchedDeviceCount == 0 {
      errPrint("warning: no supported keyboard detected — nothing will be counted until one is connected.")
    }
    print("Counting key presses for \(Int(seconds))s (only this keyboard, counts only)…")

    // Ctrl-C must still persist what was counted so far.
    signal(SIGINT, SIG_IGN)
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    interrupt.setEventHandler {
      monitor.stop()
      store.close()
      print("\nStopped. Run `kstudio stats` to see totals.")
      exit(0)
    }
    interrupt.resume()

    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
      CFRunLoopRunInMode(.defaultMode, 0.25, false)
    }
    interrupt.cancel()
    monitor.stop()
    print("Counted \(live.value) presses. Run `kstudio stats` to see totals.")
  }

  private static func day(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: date)
  }
}
