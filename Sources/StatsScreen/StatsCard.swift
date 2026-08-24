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
    let size = Screen.width
    guard let context = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return ScreenFrame(rgb: [UInt8](repeating: 0, count: size * size * 3)) }

    // Drawing happens in Core Graphics' native bottom-left space so CoreText
    // renders upright; `frame(from:)` flips the rows for the top-down panel.
    context.setFillColor(
      red: theme.background.r, green: theme.background.g, blue: theme.background.b, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))

    let textColor = CGColor(
      red: theme.text.r, green: theme.text.g, blue: theme.text.b, alpha: 1)
    let dimColor = CGColor(
      red: theme.text.r, green: theme.text.g, blue: theme.text.b, alpha: 0.55)
    let accentColor = CGColor(
      red: theme.accent.r, green: theme.accent.g, blue: theme.accent.b, alpha: 1)

    // Vertical layout, measured from the top of the 128 px panel.
    draw("TODAY", in: context, topY: 9, size: 11, color: dimColor, tracking: 1.6)

    // Press count: shrink the face when the number gets long so it always fits.
    let countText = format(presses)
    let countSize: CGFloat = countText.count > 7 ? 26 : (countText.count > 5 ? 32 : 40)
    draw(countText, in: context, topY: 24, size: countSize, color: textColor, weight: .semibold)

    let belowCount = 24 + countSize + 4
    draw(
      "\(activeMinutes) active min", in: context, topY: belowCount, size: 12, color: dimColor)
    if streak > 0 {
      draw(
        "\(streak) day streak", in: context, topY: belowCount + 16, size: 12,
        color: accentColor, weight: .medium)
    }

    drawSparkline(sparkline, in: context, accent: accentColor, dim: dimColor)

    return frame(from: context, size: size)
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

  // MARK: - Text

  enum Weight {
    case regular, medium, semibold

    var name: String {
      switch self {
      case .regular: "SFPro-Regular"
      case .medium: "SFPro-Medium"
      case .semibold: "SFPro-Semibold"
      }
    }

    var fallback: String {
      switch self {
      case .regular: "Helvetica"
      case .medium: "Helvetica"
      case .semibold: "Helvetica-Bold"
      }
    }
  }

  /// Draws one line. `topY` is the distance from the top of the panel, which is
  /// easier to lay out with than Core Graphics' bottom-left baseline origin.
  private static func draw(
    _ text: String, in context: CGContext, topY: CGFloat, x: CGFloat = 10, size: CGFloat,
    color: CGColor, weight: Weight = .regular, tracking: CGFloat = 0
  ) {
    // CoreText attribute keys, not AppKit's — this target stays UI-framework free.
    let font = CTFontCreateWithName(weight.name as CFString, size, nil)
    var attributes: [CFString: Any] = [
      kCTFontAttributeName: font,
      kCTForegroundColorAttributeName: color,
    ]
    if tracking != 0 {
      attributes[kCTTrackingAttributeName] = tracking
    }
    let attributed = CFAttributedStringCreate(
      kCFAllocatorDefault, text as CFString, attributes as CFDictionary)!
    let line = CTLineCreateWithAttributedString(attributed)
    // Cap height sits roughly 0.78 em above the baseline for these faces.
    let baseline = CGFloat(Screen.height) - topY - size * 0.78
    context.textMatrix = .identity
    context.textPosition = CGPoint(x: x, y: baseline)
    CTLineDraw(line, context)
  }

  // MARK: - Helpers

  /// Copies the bitmap out as-is: a bitmap context's backing store is already
  /// top-down (first row = top of the image), which is what the panel wants,
  /// even though drawing coordinates have their origin at the bottom-left.
  private static func frame(from context: CGContext, size: Int) -> ScreenFrame {
    guard let base = context.data else {
      return ScreenFrame(rgb: [UInt8](repeating: 0, count: size * size * 3))
    }
    let pixels = base.assumingMemoryBound(to: UInt8.self)
    var rgb = [UInt8](repeating: 0, count: size * size * 3)
    for index in 0..<(size * size) {
      rgb[index * 3] = pixels[index * 4]
      rgb[index * 3 + 1] = pixels[index * 4 + 1]
      rgb[index * 3 + 2] = pixels[index * 4 + 2]
    }
    return ScreenFrame(rgb: rgb)
  }

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
