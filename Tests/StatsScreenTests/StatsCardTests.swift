import Foundation
import KeyboardKit
import StatsCore
import Testing

@testable import StatsScreen

@Suite struct StatsCardTests {
  @Test func renderProducesAFullSizeFrame() {
    let frame = StatsCard.render(
      presses: 12_345, activeMinutes: 210, streak: 7, sparkline: [10, 40, 5, 90, 33, 60, 120],
      theme: StatsCard.Theme())
    #expect(frame.rgb.count == Screen.width * Screen.height * 3)
    #expect(frame.delayByte == 0)
  }

  @Test func renderIsNotBlank() {
    let theme = StatsCard.Theme()
    let frame = StatsCard.render(
      presses: 999, activeMinutes: 42, streak: 3, sparkline: [5, 9, 3], theme: theme)
    // Text and bars must produce pixels lighter than the background.
    let background = UInt8(theme.background.r * 255)
    let lit = stride(from: 0, to: frame.rgb.count, by: 3).contains { index in
      frame.rgb[index] > background + 40
    }
    #expect(lit)
  }

  @Test func handlesEmptyAndHugeValues() {
    let empty = StatsCard.render(
      presses: 0, activeMinutes: 0, streak: 0, sparkline: [], theme: StatsCard.Theme())
    #expect(empty.rgb.count == Screen.width * Screen.height * 3)

    let huge = StatsCard.render(
      presses: 987_654_321, activeMinutes: 99_999, streak: 4_000,
      sparkline: [Int.max / 2, 1], theme: StatsCard.Theme())
    #expect(huge.rgb.count == Screen.width * Screen.height * 3)
  }

  @Test func sevenDayWindowPadsMissingDays() throws {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("card-\(UUID().uuidString).sqlite").path
    let store = try StatsStore(path: path)
    defer { store.close(); try? FileManager.default.removeItem(atPath: path) }

    try store.flush(day: "2026-08-24", counts: [0x04: 5], hourBuckets: [9: 5], activeMinutes: 2)
    try store.flush(day: "2026-08-22", counts: [0x04: 3], hourBuckets: [9: 3], activeMinutes: 1)

    let window = try StatsCard.lastSevenDays(store: store, endingOn: "2026-08-24")
    #expect(window.count == 7)
    #expect(window.last == 5)  // 24th
    #expect(window[4] == 3)  // 22nd
    #expect(window[5] == 0)  // 23rd has no data
  }
}
