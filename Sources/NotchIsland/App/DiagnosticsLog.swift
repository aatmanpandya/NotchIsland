import Foundation

/// A small plain-text log for problems that are hard to see from outside, such as whether
/// macOS allowed the key takeover. Lives at ~/Library/Logs/NotchIsland/keys.log.
enum DiagnosticsLog {
    private static let queue = DispatchQueue(label: "notchisland.log")
    private static let url: URL = {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/NotchIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("keys.log")
    }()

    static func write(_ message: String) {
        let line = "\(Date().formatted(.iso8601)) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
