#if DIRECT_DISTRIBUTION
import AppKit

/// Direct-download edition only: the system-wide Now Playing feed, so every app works
/// (VLC, IINA, Apple TV, Podcasts, browsers without the extension, ...).
///
/// macOS only shares that feed with Apple-signed processes, so the bundled NowPlayingHelper
/// library is loaded into /usr/bin/perl, which streams JSON lines back. The App Store sandbox
/// does not allow this, which is why the App Store edition leaves this source out.
final class SystemNowPlayingSource: MediaSource {
    let id = "system"
    var onChange: (() -> Void)?
    private(set) var snapshot: PlaybackSnapshot? {
        didSet { if snapshot != oldValue { onChange?() } }
    }

    private static let loader = """
    use strict; use DynaLoader;
    my $lib = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
    my $sym = DynaLoader::dl_find_symbol($lib, "notchisland_stream") or die DynaLoader::dl_error();
    DynaLoader::dl_install_xsub("main::stream", $sym);
    stream();
    """

    private let helperURL: URL
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var artwork: (id: String, image: NSImage)?
    private var pid: pid_t = 0
    private var restartDelay: TimeInterval = 1
    private var gaveUp = false

    init?() {
        let embedded = Bundle.main.privateFrameworksURL?.appendingPathComponent("NowPlayingHelper.dylib")
        guard let url = [embedded, Bundle.main.url(forResource: "NowPlayingHelper", withExtension: "dylib")]
            .compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
        helperURL = url
        launch()
    }

    deinit {
        process?.terminate()
    }

    // MARK: - Helper process

    private func launch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.loader, helperURL.path]
        let output = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { self?.consume(data) }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.helperExited() }
        }

        do {
            try process.run()
            self.process = process
            self.input = input.fileHandleForWriting
        } catch {
            NSLog("NotchIsland: could not start Now Playing helper: %@", "\(error)")
        }
    }

    /// Restart with backoff if the helper dies, unless it reported that MediaRemote is unavailable.
    private func helperExited() {
        process = nil
        input = nil
        buffer.removeAll()
        snapshot = nil
        guard !gaveUp else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + restartDelay) { [weak self] in self?.launch() }
        restartDelay = min(restartDelay * 2, 60)
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                handle(object)
            }
        }
    }

    private func handle(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "ready":
            restartDelay = 1
        case "error":
            NSLog("NotchIsland: Now Playing helper: %@", message["message"] as? String ?? "unknown error")
            gaveUp = true
        case "state":
            update(from: message)
        default:
            break
        }
    }

    private func update(from state: [String: Any]) {
        let title = state["title"] as? String ?? ""
        let pid = pid_t(state["pid"] as? Int ?? 0)
        guard !title.isEmpty, pid > 0 else {
            snapshot = nil
            return
        }
        self.pid = pid

        let artworkID = state["artworkID"] as? String
        if let artworkID, let encoded = state["artwork"] as? String,
           let data = Data(base64Encoded: encoded), let image = NSImage(data: data) {
            artwork = (artworkID, image)
        } else if artworkID == nil {
            artwork = nil
        }

        let duration = state["duration"] as? Double ?? 0
        snapshot = PlaybackSnapshot(
            sourceID: id,
            appName: NSRunningApplication(processIdentifier: pid)?.localizedName ?? "Now Playing",
            title: title,
            artist: state["artist"] as? String ?? "",
            album: state["album"] as? String ?? "",
            artwork: artwork?.id == artworkID ? artwork?.image : nil,
            artworkID: artworkID,
            duration: duration,
            elapsed: state["elapsed"] as? Double ?? 0,
            timestamp: Date(timeIntervalSince1970: state["timestamp"] as? Double ?? Date().timeIntervalSince1970),
            isPlaying: (state["playing"] as? Bool) ?? false,
            canSeek: duration > 0
        )
    }

    // MARK: - Commands

    func send(_ command: MediaCommand) {
        let line: String
        switch command {
        case .togglePlayPause: line = "toggle"
        case .next: line = "next"
        case .previous: line = "previous"
        case .seek(let time): line = "seek \(time)"
        case .focus:
            NSRunningApplication(processIdentifier: pid)?.activate()
            return
        }
        snapshot = snapshot?.applying(command)
        try? input?.write(contentsOf: Data((line + "\n").utf8))
    }
}
#endif
