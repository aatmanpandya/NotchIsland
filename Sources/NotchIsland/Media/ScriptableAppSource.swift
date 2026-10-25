import AppKit

/// Reads and controls apps that expose an AppleScript player (Music, Spotify).
/// Updates are pushed by the app's distributed notification; AppleScript fills in the details.
final class ScriptableAppSource: MediaSource {
    struct Target {
        enum Artwork { case url, rawData }

        let appName: String
        let bundleID: String
        let notification: String
        /// Multiplier that converts the app's track duration to seconds.
        let durationScale: Double
        let artwork: Artwork

        static let music = Target(appName: "Music", bundleID: "com.apple.Music",
                                  notification: "com.apple.Music.playerInfo",
                                  durationScale: 1, artwork: .rawData)
        static let spotify = Target(appName: "Spotify", bundleID: "com.spotify.client",
                                    notification: "com.spotify.client.PlaybackStateChanged",
                                    durationScale: 0.001, artwork: .url)
    }

    let target: Target
    var id: String { target.bundleID }
    var onChange: (() -> Void)?
    private(set) var snapshot: PlaybackSnapshot? {
        didSet { if snapshot != oldValue { onChange?() } }
    }

    // NSAppleScript is not thread-safe, so each source runs its scripts on one serial queue.
    private let queue: DispatchQueue
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    init(_ target: Target) {
        self.target = target
        queue = DispatchQueue(label: "notchisland.script.\(target.appName)")

        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: .init(target.notification), object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() })

        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == target.bundleID { self?.snapshot = nil }
        })

        // Resync now and then to catch seeks made inside the app.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            if self?.snapshot?.isPlaying == true { self?.refresh() }
        }
        refresh()
    }

    private var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID)
            .contains { !$0.isTerminated }
    }

    func refresh() {
        guard isRunning else { snapshot = nil; return }
        let target = target
        let previous = snapshot
        queue.async { [weak self] in
            var next = Self.run(Self.stateScript(for: target))?.stringValue.flatMap { Self.parse($0, target: target) }
            if var s = next {
                s.artwork = s.artworkID == previous?.artworkID
                    ? previous?.artwork
                    : Self.fetchArtwork(target: target, id: s.artworkID)
                next = s
            }
            DispatchQueue.main.async { self?.snapshot = next }
        }
    }

    func send(_ command: MediaCommand) {
        if case .focus = command {
            NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).first?.activate()
            return
        }
        let verb = switch command {
        case .togglePlayPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        case .seek(let time): "set player position to \(time)"
        case .focus: ""
        }

        // Update the UI right away instead of waiting for the round trip.
        snapshot = snapshot?.applying(command)

        let script = """
        if application "\(target.appName)" is running then
            tell application "\(target.appName)" to \(verb)
        end if
        """
        queue.async { [weak self] in
            _ = Self.run(script)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.refresh() }
        }
    }

    // MARK: - AppleScript

    // `is running` guards keep a script from relaunching an app that just quit.
    private static func stateScript(for target: Target) -> String {
        let artworkLine = target.artwork == .url ? "set out to out & linefeed & (artwork url of t)" : ""
        return """
        if application "\(target.appName)" is running then
            tell application "\(target.appName)"
                try
                    set st to player state as string
                    if st is "stopped" then return "stopped"
                    set t to current track
                    set out to st & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) ¬
                        & linefeed & ((duration of t) as string) & linefeed & ((player position) as string)
                    \(artworkLine)
                    return out
                end try
            end tell
        end if
        return "stopped"
        """
    }

    private static func parse(_ output: String, target: Target) -> PlaybackSnapshot? {
        let parts = output.components(separatedBy: "\n")
        guard parts.count >= 6, parts[0] != "stopped", !parts[1].isEmpty else { return nil }
        func number(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let artworkID = target.artwork == .url ? parts[safe: 6] : "\(parts[2])|\(parts[3])"
        return PlaybackSnapshot(
            sourceID: target.bundleID, appName: target.appName,
            title: parts[1], artist: parts[2], album: parts[3],
            artwork: nil, artworkID: artworkID,
            duration: number(parts[4]) * target.durationScale,
            elapsed: number(parts[5]), timestamp: Date(),
            isPlaying: parts[0] == "playing"
        )
    }

    private static func fetchArtwork(target: Target, id: String?) -> NSImage? {
        switch target.artwork {
        case .url:
            guard let id, let url = URL(string: id), let data = try? Data(contentsOf: url) else { return nil }
            return NSImage(data: data)
        case .rawData:
            let script = """
            if application "\(target.appName)" is running then
                tell application "\(target.appName)"
                    try
                        return raw data of artwork 1 of current track
                    end try
                end tell
            end if
            """
            guard let data = run(script)?.data, !data.isEmpty else { return nil }
            return NSImage(data: data)
        }
    }

    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            NSLog("NotchIsland AppleScript error: %@", error)
            return nil
        }
        return result
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
