import XCTest
@testable import NotchIsland

final class PlaybackSnapshotTests: XCTestCase {
    private func snapshot(playing: Bool, elapsed: TimeInterval = 10, duration: TimeInterval = 100,
                          at time: Date = Date(timeIntervalSince1970: 1_000)) -> PlaybackSnapshot {
        PlaybackSnapshot(sourceID: "test", appName: "Test", title: "Song", artist: "Artist", album: "",
                         artwork: nil, artworkID: nil, duration: duration, elapsed: elapsed,
                         timestamp: time, isPlaying: playing)
    }

    func testElapsedAdvancesOnlyWhilePlaying() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(snapshot(playing: true).elapsed(at: start.addingTimeInterval(5)), 15, accuracy: 0.001)
        XCTAssertEqual(snapshot(playing: false).elapsed(at: start.addingTimeInterval(5)), 10, accuracy: 0.001)
    }

    func testElapsedStopsAtTheEnd() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(snapshot(playing: true).elapsed(at: start.addingTimeInterval(500)), 100)
    }

    func testTogglingKeepsThePositionAndFlipsPlayback() {
        let start = Date(timeIntervalSince1970: 1_000)
        let paused = snapshot(playing: true).applying(.togglePlayPause, at: start.addingTimeInterval(5))
        XCTAssertFalse(paused.isPlaying)
        XCTAssertEqual(paused.elapsed(at: start.addingTimeInterval(60)), 15, accuracy: 0.001)
    }

    func testSeekMovesThePosition() {
        let moved = snapshot(playing: false).applying(.seek(42))
        XCTAssertEqual(moved.elapsed, 42)
    }
}

private final class FakeSource: MediaSource {
    let id: String
    var snapshot: PlaybackSnapshot? { didSet { onChange?() } }
    var onChange: (() -> Void)?
    private(set) var commands: [MediaCommand] = []

    init(id: String) { self.id = id }

    func send(_ command: MediaCommand) { commands.append(command) }

    func play(_ title: String, playing: Bool = true) {
        snapshot = PlaybackSnapshot(sourceID: id, appName: id, title: title, artist: "", album: "",
                                    artwork: nil, artworkID: nil, duration: 100, elapsed: 0,
                                    timestamp: Date(), isPlaying: playing)
    }
}

final class MediaControllerTests: XCTestCase {
    func testWhateverIsPlayingWins() {
        let browser = FakeSource(id: "browser"), spotify = FakeSource(id: "spotify")
        let controller = MediaController(sources: [browser, spotify])
        browser.play("Paused video", playing: false)
        spotify.play("Song")
        XCTAssertEqual(controller.current?.title, "Song")
    }

    func testStaysOnTheLastSourceWhenEverythingPauses() {
        let browser = FakeSource(id: "browser"), spotify = FakeSource(id: "spotify")
        let controller = MediaController(sources: [browser, spotify])
        browser.play("Video", playing: false)
        spotify.play("Song")
        spotify.play("Song", playing: false)
        XCTAssertEqual(controller.current?.sourceID, "spotify")
    }

    func testCommandsGoToTheSourceBeingShown() {
        let browser = FakeSource(id: "browser"), spotify = FakeSource(id: "spotify")
        let controller = MediaController(sources: [browser, spotify])
        spotify.play("Song")
        controller.send(.next)
        XCTAssertEqual(spotify.commands.count, 1)
        XCTAssertTrue(browser.commands.isEmpty)
    }
}
