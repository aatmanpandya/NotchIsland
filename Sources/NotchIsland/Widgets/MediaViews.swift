import SwiftUI

struct MediaPanel: View {
    @ObservedObject var media: MediaController

    var body: some View {
        if let now = media.current {
            HStack(spacing: 14) {
                ArtworkView(image: now.artwork, size: 96, corner: 14)
                VStack(alignment: .leading, spacing: 3) {
                    Text(now.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(now.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    ProgressRow(now: now, tint: media.tint) { media.send(.seek($0)) }
                    HStack(spacing: 26) {
                        ControlButton(symbol: "backward.fill", size: 15) { media.send(.previous) }
                        ControlButton(symbol: now.isPlaying ? "pause.fill" : "play.fill", size: 22) {
                            media.send(.togglePlayPause)
                        }
                        ControlButton(symbol: "forward.fill", size: 15) { media.send(.next) }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 24))
                    .foregroundStyle(.tertiary)
                Text("Nothing playing")
                    .font(.system(size: 13, weight: .semibold))
                Text("Play something in Music or Spotify")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [.gray.opacity(0.5), .gray.opacity(0.2)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

private struct ProgressRow: View {
    let now: PlaybackSnapshot
    let tint: Color
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = now.elapsed(at: context.date)
            let fraction = now.duration > 0 ? min(1, elapsed / now.duration) : 0
            HStack(spacing: 8) {
                Text(Self.format(elapsed))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule().fill(tint).frame(width: geo.size.width * fraction)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { point in
                        onSeek(max(0, min(1, point.x / geo.size.width)) * now.duration)
                    }
                }
                .frame(height: 5)
                Text("-" + Self.format(max(0, now.duration - elapsed)))
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: size + 16, height: size + 12)
                .background(Circle().fill(.white.opacity(isHovered ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

/// The little equalizer shown beside the notch while audio plays.
struct AudioBars: View {
    let isPlaying: Bool
    let color: Color

    private let speeds: [Double] = [5.1, 6.7, 4.3, 7.4]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<speeds.count, id: \.self) { i in
                    let level = isPlaying ? 0.3 + 0.7 * abs(sin(t * speeds[i] + Double(i) * 1.3)) : 0.2
                    Capsule().fill(color).frame(width: 3, height: 14 * level)
                }
            }
            .frame(height: 14)
        }
    }
}
