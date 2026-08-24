import CoreGraphics
import Foundation
import K86Kit

/// Cards drawn in code rather than loaded from files.
///
/// These carry no licensing baggage — nothing is bundled or downloaded — and
/// they can show live values, which a GIF never can.
public enum GeneratedCards {
  public static func all() -> [Descriptor] {
    [
      Descriptor(id: "clock", name: "Clock", detail: "Time and date, refreshed each minute"),
      Descriptor(id: "keys-today", name: "Keys today", detail: "Your typing card"),
      Descriptor(id: "battery", name: "Battery", detail: "Mac battery level"),
      Descriptor(id: "gradient", name: "Gradient", detail: "Calibration / colour test"),
    ]
  }

  public struct Descriptor: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let detail: String
  }

  // MARK: - Clock

  public static func clock(date: Date = Date(), theme: StatsCard.Theme = StatsCard.Theme())
    -> ScreenFrame
  {
    Canvas.draw(background: theme.background) { context in
      let time = DateFormatter()
      time.dateFormat = "HH:mm"
      time.locale = Locale(identifier: "en_US_POSIX")
      let day = DateFormatter()
      day.dateFormat = "EEEE"
      let full = DateFormatter()
      full.dateFormat = "d MMMM"

      Canvas.text(
        time.string(from: date), in: context, topY: 34, size: 46, color: theme.text,
        weight: .semibold, centered: true)
      Canvas.text(
        day.string(from: date).uppercased(), in: context, topY: 86, size: 12,
        color: theme.accent, weight: .medium, tracking: 1.4, centered: true)
      Canvas.text(
        full.string(from: date), in: context, topY: 102, size: 12,
        color: (theme.text.r, theme.text.g, theme.text.b), alpha: 0.55, centered: true)
    }
  }

  // MARK: - Battery

  public static func battery(
    percent: Int, charging: Bool, theme: StatsCard.Theme = StatsCard.Theme()
  ) -> ScreenFrame {
    let level = max(0, min(100, percent))
    // Green above 50%, amber above 20%, red below — read at a glance.
    let colour: (r: Double, g: Double, b: Double) =
      level > 50 ? (0.2, 0.8, 0.4) : (level > 20 ? (0.95, 0.7, 0.2) : (0.9, 0.3, 0.3))

    return Canvas.draw(background: theme.background) { context in
      Canvas.text(
        charging ? "CHARGING" : "BATTERY", in: context, topY: 16, size: 11,
        color: theme.accent, weight: .medium, tracking: 1.5, centered: true)
      Canvas.text(
        "\(level)%", in: context, topY: 38, size: 40, color: theme.text, weight: .semibold,
        centered: true)

      let track = CGRect(x: 20, y: 26, width: 88, height: 12)
      context.setFillColor(
        red: theme.text.r, green: theme.text.g, blue: theme.text.b, alpha: 0.18)
      context.fill(track)
      context.setFillColor(red: colour.r, green: colour.g, blue: colour.b, alpha: 1)
      context.fill(
        CGRect(
          x: track.minX, y: track.minY, width: track.width * CGFloat(level) / 100,
          height: track.height))
    }
  }

  // MARK: - Gradient

  /// Sweeps hue horizontally and brightness vertically — makes RGB565 banding
  /// and any panel colour cast obvious.
  public static func gradient() -> ScreenFrame {
    var rgb = [UInt8](repeating: 0, count: Screen.width * Screen.height * 3)
    for y in 0..<Screen.height {
      let value = 1.0 - Double(y) / Double(Screen.height - 1) * 0.85
      for x in 0..<Screen.width {
        let hue = Double(x) / Double(Screen.width - 1)
        let (r, g, b) = hsv(hue: hue, saturation: 0.85, value: value)
        let index = (y * Screen.width + x) * 3
        rgb[index] = UInt8(r * 255)
        rgb[index + 1] = UInt8(g * 255)
        rgb[index + 2] = UInt8(b * 255)
      }
    }
    return ScreenFrame(rgb: rgb)
  }

  private static func hsv(hue: Double, saturation: Double, value: Double)
    -> (Double, Double, Double)
  {
    let sector = hue * 6
    let index = Int(sector) % 6
    let fraction = sector - Double(Int(sector))
    let p = value * (1 - saturation)
    let q = value * (1 - saturation * fraction)
    let t = value * (1 - saturation * (1 - fraction))
    return switch index {
    case 0: (value, t, p)
    case 1: (q, value, p)
    case 2: (p, value, t)
    case 3: (p, q, value)
    case 4: (t, p, value)
    default: (value, p, q)
    }
  }
}
