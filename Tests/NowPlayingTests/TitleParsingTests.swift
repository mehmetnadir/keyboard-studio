import Testing

@testable import NowPlaying

@Suite struct TitleParsingTests {
  @Test func desktopAppPipeFormat() {
    // Real title observed from the th-ch YouTube Music app.
    let parsed = PlayerBridge.parseYouTubeTitle(
      "J'ADORE LA VIE | Official Music Video | SilverMiC | YouTube Music")
    #expect(parsed?.title == "J'ADORE LA VIE")
    #expect(parsed?.artist == "SilverMiC")
  }

  @Test func browserTabDashFormat() {
    let parsed = PlayerBridge.parseYouTubeTitle("Bohemian Rhapsody - Queen - YouTube Music")
    #expect(parsed?.title == "Bohemian Rhapsody")
    #expect(parsed?.artist == "Queen")
  }

  @Test func stripsUnreadBadge() {
    let parsed = PlayerBridge.parseYouTubeTitle("(3) Song Name - Artist - YouTube Music")
    #expect(parsed?.title == "Song Name")
  }

  @Test func idleTitleIsNotATrack() {
    #expect(PlayerBridge.parseYouTubeTitle("YouTube Music") == nil)
    #expect(PlayerBridge.parseYouTubeTitle("") == nil)
  }

  @Test func twoSegmentPipeTitle() {
    let parsed = PlayerBridge.parseYouTubeTitle("Track Name | Artist | YouTube Music")
    #expect(parsed?.title == "Track Name")
    #expect(parsed?.artist == "Artist")
  }
}
