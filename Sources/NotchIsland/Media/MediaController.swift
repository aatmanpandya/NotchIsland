import AppKit
import CoreImage
import SwiftUI

/// Picks which source the island shows and routes commands back to it.
final class MediaController: ObservableObject {
    @Published private(set) var current: PlaybackSnapshot?
    /// Accent color taken from the current artwork.
    @Published private(set) var tint: Color = .white

    private let sources: [MediaSource]
    private var tintArtworkID: String?

    private var settingsObserver: NSObjectProtocol?

    init(sources: [MediaSource]) {
        self.sources = sources
        // Sources can be switched off in Settings.
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.recompute() }
        for source in sources {
            source.onChange = { [weak self] in self?.recompute() }
        }
        recompute()
    }

    func send(_ command: MediaCommand) {
        guard let id = current?.sourceID else { return }
        sources.first { $0.id == id }?.send(command)
    }

    /// Prefer whatever is playing; otherwise stay on the last source shown.
    private func recompute() {
        let snapshots = sources.filter { Preferences.isSourceEnabled($0.id) }.compactMap(\.snapshot)
        let next = snapshots.first(where: \.isPlaying)
            ?? snapshots.first { $0.sourceID == current?.sourceID }
            ?? snapshots.first
        if next != current { current = next }

        if next?.artworkID != tintArtworkID || (next?.artwork != nil && tint == .white) {
            tintArtworkID = next?.artworkID
            tint = next?.artwork?.accentColor.map(Color.init(nsColor:)) ?? .white
        }
    }
}

private extension NSImage {
    /// Average color, pushed bright enough to read on black.
    var accentColor: NSColor? {
        guard let tiff = tiffRepresentation, let input = CIImage(data: tiff),
              let filter = CIFilter(name: "CIAreaAverage", parameters: [
                  kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent),
              ]),
              let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            output, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil
        )
        let average = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                              blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        average.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(s * 1.2, 0.9), brightness: max(b, 0.8), alpha: 1)
    }
}
