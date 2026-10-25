import AppKit

/// What a media source is playing at a point in time.
struct PlaybackSnapshot: Equatable {
    var sourceID: String
    var appName: String
    var title: String
    var artist: String
    var album: String
    var artwork: NSImage?
    /// Changes only when the artwork changes, so it can be cached.
    var artworkID: String?
    var duration: TimeInterval
    /// Elapsed time as of `timestamp`.
    var elapsed: TimeInterval
    var timestamp: Date
    var isPlaying: Bool
    var canSeek = true
    var canSkip = true

    func elapsed(at date: Date) -> TimeInterval {
        guard isPlaying else { return elapsed }
        let value = elapsed + date.timeIntervalSince(timestamp)
        return duration > 0 ? min(value, duration) : value
    }
}

enum MediaCommand {
    case togglePlayPause
    case next
    case previous
    case seek(TimeInterval)
    /// Bring the app or browser tab that is playing to the front.
    case focus
}

/// Anything that can report playback and accept commands: a scriptable app,
/// the browser extension bridge, or (direct-download edition) system Now Playing.
protocol MediaSource: AnyObject {
    var id: String { get }
    var snapshot: PlaybackSnapshot? { get }
    var onChange: (() -> Void)? { get set }
    func send(_ command: MediaCommand)
}
