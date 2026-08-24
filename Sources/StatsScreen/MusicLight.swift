import Foundation
import KeyboardKit
import NowPlaying

/// Tying the keyboard's lighting to what is playing.
///
/// ## What the hardware allows
///
/// Not a real-time visualiser, and it is worth being precise about why. Two
/// hard limits, both measured rather than assumed:
///
/// - **Lighting commands are rate-limited.** Pushing them faster than roughly
///   one or two a second wedges the control endpoint, and a wedged endpoint
///   stops answering until the keyboard is physically re-plugged.
/// - **Per-key colour writes flash**, with a ten-second floor between uploads,
///   so per-key animation would burn out the cells long before it looked good.
///
/// So a beat-synced strobe is off the table on this hardware. What does work is
/// a colour that belongs to the track and drifts slowly while it plays: one
/// update every couple of seconds, well inside the safe rate.
public enum MusicLight {
  /// How often the colour may be refreshed. Deliberately conservative.
  public static let updateInterval: TimeInterval = 2.0

  /// A stable colour for a track.
  ///
  /// Album art would be the obvious source, but fetching it needs network
  /// access the app does not have. Deriving the hue from the title instead
  /// gives every track its own identity, and the same track always gets the
  /// same colour — which reads as intentional rather than random.
  public static func color(
    for playing: NowPlaying, drift: Double = 0, saturation: Double = 0.85
  ) -> RGB {
    let base = hue(for: playing.title + playing.artist)
    let shifted = (base + drift).truncatingRemainder(dividingBy: 1)
    return rgb(hue: shifted < 0 ? shifted + 1 : shifted, saturation: saturation, value: 1)
  }

  /// Drift across the track: a slow sweep of about a sixth of the colour wheel,
  /// so a long song visibly moves without ever becoming distracting.
  public static func drift(progress: Double?) -> Double {
    guard let progress else { return 0 }
    return min(max(progress, 0), 1) * 0.17
  }

  /// Deterministic hue from a string — same track, same colour, every time.
  static func hue(for text: String) -> Double {
    var hash: UInt64 = 5381
    for byte in text.utf8 {
      hash = (hash &* 33) &+ UInt64(byte)
    }
    return Double(hash % 1000) / 1000
  }

  static func rgb(hue: Double, saturation: Double, value: Double) -> RGB {
    let sector = hue * 6
    let index = Int(sector) % 6
    let fraction = sector - Double(Int(sector))
    let p = value * (1 - saturation)
    let q = value * (1 - saturation * fraction)
    let t = value * (1 - saturation * (1 - fraction))
    let (r, g, b): (Double, Double, Double) = switch index {
    case 0: (value, t, p)
    case 1: (q, value, p)
    case 2: (p, value, t)
    case 3: (p, q, value)
    case 4: (t, p, value)
    default: (value, p, q)
    }
    return RGB(UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
  }
}
