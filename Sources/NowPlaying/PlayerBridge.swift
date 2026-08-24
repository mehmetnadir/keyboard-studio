import AppKit
import Foundation

/// Asks the running players what they are doing.
///
/// Apple Music and Spotify answer Apple Events directly. YouTube Music has no
/// scripting interface, so its track is read from the browser tab's title —
/// crude, but it is what every tool in this space does, and it needs no
/// extension installed.
public enum PlayerBridge {
  /// Players in the order they are preferred when more than one is playing.
  public static func current(preferring order: [NowPlaying.Source] = NowPlaying.Source.allCases)
    -> NowPlaying?
  {
    for source in order where isRunning(source) {
      if let playing = read(source) { return playing }
    }
    return nil
  }

  public static func isRunning(_ source: NowPlaying.Source) -> Bool {
    let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
    return source.bundleIDs.contains { running.contains($0) }
  }

  static func read(_ source: NowPlaying.Source) -> NowPlaying? {
    switch source {
    case .appleMusic: readMusicApp(name: "Music", source: .appleMusic)
    case .spotify: readMusicApp(name: "Spotify", source: .spotify)
    case .youtubeMusic: readYouTubeMusic()
    }
  }

  // MARK: - Apple Music / Spotify

  /// Both expose the same scripting vocabulary, so one script covers them.
  private static func readMusicApp(name: String, source: NowPlaying.Source) -> NowPlaying? {
    let script = """
      tell application "\(name)"
        if it is running and player state is playing then
          set t to current track
          set p to 0
          try
            set d to duration of t
            if d > 0 then set p to (player position) / d
          end try
          return (name of t) & "\u{1F}" & (artist of t) & "\u{1F}" & (album of t) & "\u{1F}" & p
        end if
      end tell
      return ""
      """
    guard let output = runAppleScript(script), !output.isEmpty else { return nil }
    let parts = output.components(separatedBy: "\u{1F}")
    guard parts.count >= 2, !parts[0].isEmpty else { return nil }
    return NowPlaying(
      title: parts[0], artist: parts[1],
      album: parts.count > 2 && !parts[2].isEmpty ? parts[2] : nil,
      progress: parts.count > 3 ? Double(parts[3]).map { min(max($0, 0), 1) } : nil,
      source: source)
  }

  // MARK: - YouTube Music

  /// Reads the tab title, which YouTube Music formats as "Title - Artist".
  /// A paused tab drops the leading marker, so we can tell playing from not.
  private static func readYouTubeMusic() -> NowPlaying? {
    let browsers = [
      ("Google Chrome", "com.google.Chrome"), ("Brave Browser", "com.brave.Browser"),
      ("Arc", "company.thebrowser.Browser"), ("Microsoft Edge", "com.microsoft.edgemac"),
      ("Safari", "com.apple.Safari"),
    ]
    let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)

    for (appName, bundleID) in browsers where running.contains(bundleID) {
      let script = appName == "Safari"
        ? """
          tell application "Safari"
            repeat with w in windows
              repeat with t in tabs of w
                if URL of t contains "music.youtube.com" then return name of t
              end repeat
            end repeat
          end tell
          return ""
          """
        : """
          tell application "\(appName)"
            repeat with w in windows
              repeat with t in tabs of w
                if URL of t contains "music.youtube.com" then return title of t
              end repeat
            end repeat
          end tell
          return ""
          """
      guard let title = runAppleScript(script), !title.isEmpty else { continue }
      if let parsed = parseYouTubeTitle(title) { return parsed }
    }
    return nil
  }

  /// "Song - Artist - YouTube Music", sometimes prefixed with a play marker
  /// and a notification count like "(2)".
  static func parseYouTubeTitle(_ raw: String) -> NowPlaying? {
    var text = raw
    for suffix in [" - YouTube Music", " – YouTube Music"] where text.hasSuffix(suffix) {
      text = String(text.dropLast(suffix.count))
    }
    // Strip a leading "(3) " unread badge.
    if text.hasPrefix("("), let close = text.firstIndex(of: ")") {
      text = String(text[text.index(after: close)...]).trimmingCharacters(in: .whitespaces)
    }
    guard !text.isEmpty, text != "YouTube Music" else { return nil }

    let parts = text.components(separatedBy: " - ")
    if parts.count >= 2 {
      return NowPlaying(
        title: parts[0].trimmingCharacters(in: .whitespaces),
        artist: parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces),
        source: .youtubeMusic)
    }
    return NowPlaying(title: text, artist: "", source: .youtubeMusic)
  }

  // MARK: - Apple Events

  private static func runAppleScript(_ source: String) -> String? {
    var error: NSDictionary?
    guard let script = NSAppleScript(source: source) else { return nil }
    let result = script.executeAndReturnError(&error)
    if error != nil { return nil }
    return result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
