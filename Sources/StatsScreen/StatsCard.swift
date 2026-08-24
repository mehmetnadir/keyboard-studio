import CoreGraphics
import CoreText
import Foundation
import K86Kit
import StatsCore

/// Renders typing statistics as a 128×128 frame for the keyboard's own screen.
///
/// No other keyboard software puts your own numbers on the device; this is the
/// payoff for having both halves of the project in one app.
public enum StatsCard {
  public struct Theme: Sendable {
    public var background: (r: Double, g: Double, b: Double)
    public var text: (r: Double, g: Double, b: Double)
    public var accent: (r: Double, g: Double, b: Double)

    public init(
      background: (r: Double, g: Double, b: Double) = (0.05, 0.05, 0.07),
      text: (r: Double, g: Double, b: Double) = (0.93, 0.93, 0.95),
      accent: (r: Double, g: Double, b: Double) = (0.61, 0.35, 0.71)
    ) {
      self.background = background
      self.text = text
      self.accent = accent
    }
  }

  /// Builds today's card: press count, active minutes, streak, 7-day sparkline.
  public static func today(store: StatsStore, theme: Theme = Theme()) throws -> ScreenFrame {
    let today = todayLocal()
    let stat = try store.dayStat(today)
    let records = try store.records()
    let recent = try lastSevenDays(store: store, endingOn: today)
    return render(
      presses: stat?.presses ?? 0, activeMinutes: stat?.activeMinutes ?? 0,
      streak: records.currentStreak, sparkline: recent, theme: theme)
  }

  static func lastSevenDays(store: StatsStore, endingOn day: String) throws -> [Int] {
    let all = try store.allDays()
    let byDay = Dictionary(uniqueKeysWithValues: all.map { ($0.day, $0.presses) })
    guard let end = parse(day) else { return [] }
    return (0..<7).reversed().compactMap { offset in
      guard let date = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
      return byDay[dayString(date)] ?? 0
    }
  }

  // MARK: - Drawing

  /// Draws a card from explicit values — used for previews and tests.
  public static func render(
    presses: Int, activeMinutes: Int, streak: Int, sparkline: [Int], theme: Theme = Theme()
  ) -> ScreenFrame {
    Canvas.draw(background: theme.background) { context in
      // Vertical layout, measured from the top of the 128 px panel.
      Canvas.text(
        "TODAY", in: context, topY: 9, size: 11, color: theme.text, alpha: 0.55, tracking: 1.6)

      // Press count: shrink the face when the number gets long so it always fits.
      let countText = format(presses)
      let countSize: CGFloat = countText.count > 7 ? 26 : (countText.count > 5 ? 32 : 40)
      Canvas.text(
        countText, in: context, topY: 24, size: countSize, color: theme.text, weight: .semibold)

      let belowCount = 24 + countSize + 4
      Canvas.text(
        "\(activeMinutes) active min", in: context, topY: belowCount, size: 12,
        color: theme.text, alpha: 0.55)
      if streak > 0 {
        Canvas.text(
          "\(streak) day streak", in: context, topY: belowCount + 16, size: 12,
          color: theme.accent, weight: .medium)
      }

      drawSparkline(
        sparkline, in: context,
        accent: CGColor(red: theme.accent.r, green: theme.accent.g, blue: theme.accent.b, alpha: 1),
        dim: CGColor(red: theme.text.r, green: theme.text.g, blue: theme.text.b, alpha: 0.55))
    }
  }

  private static func drawSparkline(
    _ values: [Int], in context: CGContext, accent: CGColor, dim: CGColor
  ) {
    guard !values.isEmpty else { return }
    let baseline: CGFloat = 10  // bottom-left space: 10 px above the panel edge
    let maxHeight: CGFloat = 30
    let width: CGFloat = 12
    let gap: CGFloat = 4
    let peak = max(values.max() ?? 1, 1)

    for (index, value) in values.enumerated() {
      let height = max(2, CGFloat(value) / CGFloat(peak) * maxHeight)
      let x = 10 + CGFloat(index) * (width + gap)
      // Today (the last bar) is the accent colour; earlier days recede.
      context.setFillColor(index == values.count - 1 ? accent : dim)
      context.fill(CGRect(x: x, y: baseline, width: width, height: height))
    }
  }

  // MARK: - Helpers

  private static func format(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = " "
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
  }

  static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar
  }()

  /// Day keys are stored in UTC only for stepping between them; the *current*
  /// day must be resolved locally so it matches what `KeyMonitor` writes.
  private static let keyFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter
  }()

  private static let localFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
  }()

  static func todayLocal() -> String {
    localFormatter.string(from: Date())
  }

  static func dayString(_ date: Date) -> String {
    keyFormatter.string(from: date)
  }

  static func parse(_ day: String) -> Date? {
    keyFormatter.date(from: day)
  }
}
