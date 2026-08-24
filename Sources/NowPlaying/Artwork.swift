import AppKit
import Foundation

/// Album art, when the player can hand it over without the network.
///
/// Only Apple Music can: its scripting interface returns the raw image data
/// already on disk. Spotify exposes an artwork *URL*, which would mean an HTTP
/// fetch — something this app cannot do and does not want to. YouTube Music
/// offers nothing but a window title.
///
/// So art-derived colour is a real feature on Apple Music and an honest "not
/// available" elsewhere, rather than a promise that quietly does nothing.
public enum Artwork {
  /// Which sources can supply art locally.
  public static func isAvailable(for source: NowPlaying.Source) -> Bool {
    source == .appleMusic
  }

  /// Writes the current track's art to a temporary file and loads it.
  ///
  /// The round-trip through disk is how AppleScript hands over binary data;
  /// the file lives in the app's own container and is removed immediately.
  public static func current(for source: NowPlaying.Source) -> NSImage? {
    guard isAvailable(for: source) else { return nil }

    let file = FileManager.default.temporaryDirectory
      .appendingPathComponent("nowplaying-art.tiff")
    let path = file.path
    let script = """
      tell application "Music"
        if it is not running then return "no"
        try
          set theData to raw data of artwork 1 of current track
        on error
          return "no"
        end try
        set theFile to open for access (POSIX file "\(path)") with write permission
        set eof theFile to 0
        write theData to theFile
        close access theFile
        return "ok"
      end tell
      """

    var error: NSDictionary?
    guard let apple = NSAppleScript(source: script) else { return nil }
    let result = apple.executeAndReturnError(&error)
    guard error == nil, result.stringValue == "ok" else { return nil }

    defer { try? FileManager.default.removeItem(at: file) }
    return NSImage(contentsOf: file)
  }

  /// The colour that best represents an image.
  ///
  /// Averaging whole covers gives mud, so this bins pixels by hue and picks the
  /// most represented vivid one — nearly greyscale and very dark pixels are
  /// skipped, since a cover's black borders should not decide the colour.
  public static func dominantColor(of image: NSImage) -> (r: UInt8, g: UInt8, b: UInt8)? {
    guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff)
    else { return nil }

    let width = min(bitmap.pixelsWide, 64)
    let height = min(bitmap.pixelsHigh, 64)
    guard width > 0, height > 0 else { return nil }
    let stepX = max(1, bitmap.pixelsWide / width)
    let stepY = max(1, bitmap.pixelsHigh / height)

    var bins = [Int](repeating: 0, count: 36)
    var sums = [(r: Int, g: Int, b: Int)](repeating: (0, 0, 0), count: 36)

    for y in stride(from: 0, to: bitmap.pixelsHigh, by: stepY) {
      for x in stride(from: 0, to: bitmap.pixelsWide, by: stepX) {
        guard let color = bitmap.colorAt(x: x, y: y)?
          .usingColorSpace(.sRGB) else { continue }
        let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
        let maxC = max(r, g, b), minC = min(r, g, b)
        let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
        // Skip near-grey and near-black: borders and shadows, not the subject.
        guard saturation > 0.25, maxC > 0.2 else { continue }

        var hue = color.hueComponent * 36
        if hue >= 36 { hue = 35 }
        let bin = Int(hue)
        bins[bin] += 1
        sums[bin] = (
          sums[bin].r + Int(r * 255), sums[bin].g + Int(g * 255), sums[bin].b + Int(b * 255))
      }
    }

    guard let best = bins.indices.max(by: { bins[$0] < bins[$1] }), bins[best] > 0 else {
      return nil
    }
    let count = bins[best]
    return (
      UInt8(clamping: sums[best].r / count),
      UInt8(clamping: sums[best].g / count),
      UInt8(clamping: sums[best].b / count))
  }
}
