import Foundation
import Testing

@testable import StatsCore

/// Exercises the counting logic directly through `record(usage:at:)`, so no
/// keyboard and no Input Monitoring permission are involved.
@Suite struct KeyMonitorTests {
  private func makeStore() throws -> (StatsStore, String) {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("km-\(UUID().uuidString).sqlite").path
    return (try StatsStore(path: path), path)
  }

  private func date(_ iso: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    return formatter.date(from: iso)!
  }

  @Test func countsPressesPerKey() throws {
    let (store, path) = try makeStore()
    defer { store.close(); try? FileManager.default.removeItem(atPath: path) }

    let monitor = KeyMonitor(store: store)
    let when = date("2026-08-24 14:30:00")
    monitor.record(usage: 0x04, at: when)
    monitor.record(usage: 0x04, at: when)
    monitor.record(usage: 0x2C, at: when)
    try monitor.flush()

    let stat = try store.dayStat("2026-08-24")
    #expect(stat?.presses == 3)
    let top = try store.topKeys(from: "2026-08-24", to: "2026-08-24", limit: 5)
    #expect(top.first == KeyStat(keycode: 0x04, count: 2))
  }

  @Test func activeMinutesCountDistinctMinutesOnly() throws {
    let (store, path) = try makeStore()
    defer { store.close(); try? FileManager.default.removeItem(atPath: path) }

    let monitor = KeyMonitor(store: store)
    // Three presses inside one minute, then one in the next minute.
    monitor.record(usage: 0x04, at: date("2026-08-24 09:00:01"))
    monitor.record(usage: 0x05, at: date("2026-08-24 09:00:30"))
    monitor.record(usage: 0x06, at: date("2026-08-24 09:00:59"))
    monitor.record(usage: 0x07, at: date("2026-08-24 09:01:05"))
    try monitor.flush()

    #expect(try store.dayStat("2026-08-24")?.activeMinutes == 2)
  }

  @Test func crossingMidnightSplitsDays() throws {
    let (store, path) = try makeStore()
    defer { store.close(); try? FileManager.default.removeItem(atPath: path) }

    let monitor = KeyMonitor(store: store)
    monitor.record(usage: 0x04, at: date("2026-08-24 23:59:50"))
    monitor.record(usage: 0x05, at: date("2026-08-25 00:00:10"))
    monitor.record(usage: 0x06, at: date("2026-08-25 00:00:20"))
    try monitor.flush()

    #expect(try store.dayStat("2026-08-24")?.presses == 1)
    #expect(try store.dayStat("2026-08-25")?.presses == 2)
  }

  @Test func flushIsIdempotentWhenEmpty() throws {
    let (store, path) = try makeStore()
    defer { store.close(); try? FileManager.default.removeItem(atPath: path) }

    let monitor = KeyMonitor(store: store)
    try monitor.flush()
    try monitor.flush()
    #expect(try store.lifetimeTotal() == 0)
  }

  @Test func flushClearsPendingCounts() throws {
    let (store, path) = try makeStore()
    defer { store.close(); try? FileManager.default.removeItem(atPath: path) }

    let monitor = KeyMonitor(store: store)
    monitor.record(usage: 0x04, at: date("2026-08-24 10:00:00"))
    try monitor.flush()
    try monitor.flush()  // a second flush must not double-count
    #expect(try store.lifetimeTotal() == 1)
  }

  @Test func keyNamesCoverLettersDigitsAndModifiers() {
    #expect(KeyNames.name(for: 0x04) == "A")
    #expect(KeyNames.name(for: 0x1D) == "Z")
    #expect(KeyNames.name(for: 0x1E) == "1")
    #expect(KeyNames.name(for: 0x2C) == "Space")
    #expect(KeyNames.name(for: 0x3A) == "F1")
    #expect(KeyNames.name(for: 0xE1) == "Left Shift")
    #expect(KeyNames.category(for: 0x04) == .letter)
    #expect(KeyNames.category(for: 0xE3) == .modifier)
  }
}
