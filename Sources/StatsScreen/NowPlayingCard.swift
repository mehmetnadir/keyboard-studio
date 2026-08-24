import CoreGraphics
import Foundation
import KeyboardKit
import NowPlaying

/// Renders what is playing onto the keyboard's screen.
///
/// Text only, deliberately: album art would mean fetching from the network, and
/// the app has no network access by design. A clear title at a legible size
/// reads better on a small panel than a shrunken cover anyway.
public enum NowPlayingCard {
  public static func render(
    _ playing: NowPlaying, theme: StatsCard.Theme = StatsCard.Theme(),
    width: Int = Screen.width, height: Int = Screen.height
  ) -> ScreenFrame {
    Canvas.draw(background: theme.background, width: width, height: height) { context in
      Canvas.text(
        playing.source.rawValue.uppercased(), in: context, topY: 10, size: 10,
        color: theme.accent, weight: .medium, tracking: 1.4, width: width, height: height)

      // Title gets the room; wrap to two lines before shrinking further.
      let titleLines = wrap(playing.title, limit: 16, maxLines: 2)
      var y: CGFloat = 30
      let titleSize: CGFloat = titleLines.count > 1 ? 17 : 21
      for line in titleLines {
        Canvas.text(
          line, in: context, topY: y, size: titleSize, color: theme.text,
          weight: .semibold, width: width, height: height)
        y += titleSize + 3
      }

      for line in wrap(playing.artist, limit: 20, maxLines: 2) {
        Canvas.text(
          line, in: context, topY: y + 4, size: 12, color: theme.text, alpha: 0.6,
          width: width, height: height)
        y += 15
      }

      if let progress = playing.progress {
        let track = CGRect(x: 10, y: 12, width: CGFloat(width) - 20, height: 5)
        context.setFillColor(
          red: theme.text.r, green: theme.text.g, blue: theme.text.b, alpha: 0.18)
        context.fill(track)
        context.setFillColor(
          red: theme.accent.r, green: theme.accent.g, blue: theme.accent.b, alpha: 1)
        context.fill(
          CGRect(
            x: track.minX, y: track.minY,
            width: track.width * CGFloat(min(max(progress, 0), 1)), height: track.height))
      }
    }
  }

  /// Greedy word wrap, falling back to hard truncation for a single long word.
  static func wrap(_ text: String, limit: Int, maxLines: Int) -> [String] {
    guard !text.isEmpty else { return [] }
    var lines: [String] = []
    var current = ""
    for word in text.split(separator: " ") {
      let candidate = current.isEmpty ? String(word) : current + " " + word
      if candidate.count <= limit {
        current = candidate
      } else {
        if !current.isEmpty { lines.append(current) }
        current = String(word.prefix(limit))
      }
      if lines.count == maxLines { break }
    }
    if lines.count < maxLines, !current.isEmpty { lines.append(current) }
    if lines.count == maxLines, let last = lines.last, last.count >= limit {
      lines[lines.count - 1] = String(last.dropLast(1)) + "…"
    }
    return lines
  }
}
