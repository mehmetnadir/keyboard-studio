import Foundation
import KeyboardKit

/// `kstudio measure` — finds the panel's real resolution.
///
/// The firmware reports "ready" for any frame size, and oversized frames just
/// blank the panel, so the size cannot be asked for. Instead this paints a
/// known-good tile at increasing offsets: the stripes that appear mark the area
/// the panel actually has.
enum MeasureCommand {
  private static let palette: [(name: String, rgb: (UInt8, UInt8, UInt8))] = [
    ("red", (255, 60, 60)), ("orange", (255, 150, 30)), ("yellow", (255, 240, 60)),
    ("green", (70, 220, 90)), ("cyan", (60, 200, 235)), ("blue", (80, 110, 255)),
    ("purple", (200, 90, 230)), ("white", (255, 255, 255)),
  ]

  static func run(_ args: [String]) throws {
    let kb = try Keyboard()
    defer { kb.close() }

    let stripe = intOption("--stripe", args, default: 32, range: 8...128)
    let height = intOption("--height", args, default: 128, range: 8...512)
    let span = intOption("--span", args, default: 8, range: 1...16)

    print("Painting \(span) stripes of \(stripe)×\(height), left to right…")
    var painted: [String] = []
    for index in 0..<span {
      let colour = palette[index % palette.count]
      let tile = Screen.solid(colour.rgb, width: stripe, height: height)
      let x = index * stripe
      // The firmware needs a breather between partial writes; back-to-back
      // handshakes get refused even for offsets it accepts on their own.
      var attempt = 0
      while true {
        do {
          try Screen.writeImage(tile, at: (x: x, y: 0), on: kb)
          painted.append("\(colour.name)@\(x)")
          break
        } catch {
          attempt += 1
          guard attempt < 3 else {
            print("  refused at x=\(x) after \(attempt) attempts")
            break
          }
          Thread.sleep(forTimeInterval: 0.4)
        }
      }
      Thread.sleep(forTimeInterval: 0.25)
    }

    print("Sent: \(painted.joined(separator: " "))")
    print(
      """

      Count the stripes you can actually see on the keyboard:
        width = (number of stripes) × \(stripe)
      The colour order is: \(palette.map(\.name).joined(separator: " → "))
      """)
  }
}
