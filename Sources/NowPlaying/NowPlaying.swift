import Foundation

/// What is playing right now, from whichever player is actually running.
///
/// Everything here is local: players are asked over Apple Events, and the
/// browser sources read a tab's title. Nothing reaches the network, which is
/// what keeps the app's no-network guarantee intact.
public struct NowPlaying: Sendable, Equatable {
  public var title: String
  public var artist: String
  public var album: String?
  /// 0…1 through the track, when the player reports it.
  public var progress: Double?
  public var source: Source

  public enum Source: String, Sendable, CaseIterable {
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case youtubeMusic = "YouTube Music"

    /// Bundle ids checked before asking, so we never trigger a permission
    /// prompt for an app that is not even running.
    var bundleIDs: [String] {
      switch self {
      case .appleMusic: ["com.apple.Music"]
      case .spotify: ["com.spotify.client"]
      case .youtubeMusic: [
        "com.google.Chrome", "com.brave.Browser", "com.apple.Safari",
        "company.thebrowser.Browser", "com.microsoft.edgemac",
        "com.github.th-ch.youtube-music",
      ]
      }
    }
  }

  public init(
    title: String, artist: String, album: String? = nil, progress: Double? = nil,
    source: Source
  ) {
    self.title = title
    self.artist = artist
    self.album = album
    self.progress = progress
    self.source = source
  }
}
