import Testing
import Foundation

@testable import StatsCore

@Suite struct StatsStoreTests {
  private func makeTempStore() throws -> (store: StatsStore, path: String) {
    let path: String = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".sqlite").path
    let store: StatsStore = try StatsStore(path: path)
    return (store, path)
  }

  private func cleanup(path: String) {
    let fm: FileManager = FileManager.default
    try? fm.removeItem(atPath: path)
    try? fm.removeItem(atPath: path + "-wal")
    try? fm.removeItem(atPath: path + "-shm")
  }

  @Test func flushRoundTrip() throws {
    let (store, path) = try makeTempStore()
    defer {
      store.close()
      cleanup(path: path)
    }

    let day: String = "2024-01-15"
    let counts: [Int: Int] = [1: 10, 2: 20]
    let hourBuckets: [Int: Int] = [9: 15, 10: 15]
    let activeMinutes: Int = 45

    try store.flush(
      day: day,
      counts: counts,
      hourBuckets: hourBuckets,
      activeMinutes: activeMinutes
    )

    let total: Int = try store.lifetimeTotal()
    #expect(total == 30)

    let stat: DayStat? = try store.dayStat(day)
    let unwrapped: DayStat = try #require(stat)
    #expect(unwrapped.day == day)
    #expect(unwrapped.presses == 30)
    #expect(unwrapped.activeMinutes == 45)
  }

  @Test func flushAccumulatesCountsOnSameDay() throws {
    let (store, path) = try makeTempStore()
    defer {
      store.close()
      cleanup(path: path)
    }

    let day: String = "2024-01-15"
    try store.flush(day: day, counts: [1: 10, 2: 5], hourBuckets: [9: 15], activeMinutes: 20)
    try store.flush(
      day: day,
      counts: [1: 15, 2: 10, 3: 7],
      hourBuckets: [10: 17],
      activeMinutes: 25
    )

    let stat: DayStat? = try store.dayStat(day)
    let unwrapped: DayStat = try #require(stat)
    #expect(unwrapped.presses == 47)
    #expect(unwrapped.activeMinutes == 45)

    let topKeys: [KeyStat] = try store.topKeys(from: day, to: day, limit: 10)
    #expect(
      topKeys == [
        KeyStat(keycode: 1, count: 25),
        KeyStat(keycode: 2, count: 15),
        KeyStat(keycode: 3, count: 7),
      ])
  }

  @Test func topKeysOrderingAndLimit() throws {
    let (store, path) = try makeTempStore()
    defer {
      store.close()
      cleanup(path: path)
    }

    let day: String = "2024-01-15"
    let counts: [Int: Int] = [
      10: 50,
      20: 10,
      30: 100,
      40: 30,
      50: 80,
      60: 5,
    ]
    try store.flush(day: day, counts: counts, hourBuckets: [:], activeMinutes: 30)

    let top3: [KeyStat] = try store.topKeys(from: day, to: day, limit: 3)
    #expect(top3.count == 3)
    #expect(
      top3 == [
        KeyStat(keycode: 30, count: 100),
        KeyStat(keycode: 50, count: 80),
        KeyStat(keycode: 10, count: 50),
      ])
  }

  @Test func totalInclusiveBoundaryCheck() throws {
    let (store, path) = try makeTempStore()
    defer {
      store.close()
      cleanup(path: path)
    }

    try store.flush(day: "2024-01-01", counts: [1: 100], hourBuckets: [:], activeMinutes: 10)
    try store.flush(day: "2024-01-02", counts: [1: 200], hourBuckets: [:], activeMinutes: 10)
    try store.flush(day: "2024-01-03", counts: [1: 300], hourBuckets: [:], activeMinutes: 10)

    let middleTotal: Int = try store.total(from: "2024-01-02", to: "2024-01-02")
    #expect(middleTotal == 200)

    // Excludes 01-03: the day after the range must not contribute.
    let rangeTotal: Int = try store.total(from: "2024-01-01", to: "2024-01-02")
    #expect(rangeTotal == 300)

    let allTotal: Int = try store.total(from: "2024-01-01", to: "2024-01-03")
    #expect(allTotal == 600)
  }

  @Test func consecutiveDaysStreak() throws {
    let (store, path) = try makeTempStore()
    defer {
      store.close()
      cleanup(path: path)
    }

    try store.flush(day: "2024-01-01", counts: [1: 10], hourBuckets: [:], activeMinutes: 5)
    try store.flush(day: "2024-01-02", counts: [1: 10], hourBuckets: [:], activeMinutes: 5)
    try store.flush(day: "2024-01-03", counts: [1: 10], hourBuckets: [:], activeMinutes: 5)

    let records: Records = try store.records()
    #expect(records.currentStreak == 3)
    #expect(records.longestStreak == 3)
  }

  @Test func streakWithGap() throws {
    let (store, path) = try makeTempStore()
    defer {
      store.close()
      cleanup(path: path)
    }

    try store.flush(day: "2024-01-01", counts: [1: 10], hourBuckets: [:], activeMinutes: 5)
    try store.flush(day: "2024-01-02", counts: [1: 10], hourBuckets: [:], activeMinutes: 5)
    try store.flush(day: "2024-01-03", counts: [1: 10], hourBuckets: [:], activeMinutes: 5)
    try store.flush(day: "2024-01-04", counts: [1: 10], hourBuckets: [:], activeMinutes: 5)

    // Gap: 01-05 through 01-09 have no activity before this single day.
    try store.flush(day: "2024-01-10", counts: [1: 10], hourBuckets: [:], activeMinutes: 5)

    let records: Records = try store.records()
    #expect(records.currentStreak == 1)
    #expect(records.longestStreak == 4)
  }

  @Test func peakHourCalculation() throws {
    let (store, path) = try makeTempStore()
    defer {
      store.close()
      cleanup(path: path)
    }

    try store.flush(
      day: "2024-01-01",
      counts: [1: 100],
      hourBuckets: [8: 20, 14: 50, 20: 30],
      activeMinutes: 30
    )
    try store.flush(
      day: "2024-01-02",
      counts: [1: 100],
      hourBuckets: [8: 10, 14: 60, 20: 30],
      activeMinutes: 30
    )

    let records: Records = try store.records()
    #expect(records.peakHour == 14)
  }

  @Test func emptyDatabaseDefaults() throws {
    let (store, path) = try makeTempStore()
    defer {
      store.close()
      cleanup(path: path)
    }

    let records: Records = try store.records()
    #expect(records.busiestDay == nil)
    #expect(records.currentStreak == 0)
    #expect(records.longestStreak == 0)
    #expect(records.peakHour == nil)

    let lifetime: Int = try store.lifetimeTotal()
    #expect(lifetime == 0)

    let days: [DayStat] = try store.allDays()
    #expect(days.isEmpty)
  }

  @Test func persistenceAcrossReopen() throws {
    let (store, path) = try makeTempStore()
    defer { cleanup(path: path) }

    let day: String = "2024-01-15"
    try store.flush(day: day, counts: [1: 42], hourBuckets: [12: 42], activeMinutes: 15)
    store.close()

    let reopenedStore: StatsStore = try StatsStore(path: path)
    defer { reopenedStore.close() }

    let total: Int = try reopenedStore.lifetimeTotal()
    #expect(total == 42)

    let stat: DayStat? = try reopenedStore.dayStat(day)
    let unwrapped: DayStat = try #require(stat)
    #expect(unwrapped.day == day)
    #expect(unwrapped.presses == 42)
    #expect(unwrapped.activeMinutes == 15)
  }
}
