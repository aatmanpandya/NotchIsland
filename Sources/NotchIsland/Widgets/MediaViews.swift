import SwiftUI

struct MediaPanel: View {
    @ObservedObject var media: MediaController
    let namespace: Namespace.ID

    var body: some View {
        if let now = media.current {
            HStack(spacing: 16) {
                Button { media.send(.focus) } label: {
                    ArtworkView(image: now.artwork, size: 104, corner: 18)
                        .matchedGeometryEffect(id: IslandMotion.artworkID, in: namespace)
                        .shadow(color: media.tint.opacity(0.45), radius: 16, y: 6)
                        .scaleEffect(now.isPlaying ? 1 : 0.9)
                        .animation(.spring(response: 0.45, dampingFraction: 0.65), value: now.isPlaying)
                }
                .buttonStyle(PressScaleStyle())
                .help("Open \(now.appName)")
                .accessibilityLabel("Open \(now.appName)")

                VStack(alignment: .leading, spacing: 2) {
                    Label(now.appName, systemImage: now.sourceID == "browser" ? "play.rectangle.fill" : "music.note")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(media.tint)
                        .lineLimit(1)
                    Text(now.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(now.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    ProgressRow(now: now, tint: media.tint) { media.send(.seek($0)) }
                        .padding(.bottom, 6)
                    HStack(spacing: 30) {
                        ControlButton(symbol: "backward.fill", size: 16, enabled: now.canSkip || now.canSeek) {
                            media.send(.previous)
                        }
                        .accessibilityLabel("Previous track")
                        PlayButton(isPlaying: now.isPlaying) { media.send(.togglePlayPause) }
                        ControlButton(symbol: "forward.fill", size: 16, enabled: now.canSkip) {
                            media.send(.next)
                        }
                        .accessibilityLabel("Next track")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white.opacity(0.06))
                    Image(systemName: "music.note")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .frame(width: 104, height: 104)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nothing playing")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Play music or video in Music, Spotify, or your browser.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
                    LinearGradient(colors: [Color(white: 0.28), Color(white: 0.14)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.38, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 0.5))
    }
}

private struct ProgressRow: View {
    let now: PlaybackSnapshot
    let tint: Color
    let onSeek: (TimeInterval) -> Void
    @State private var isHovered = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let elapsed = now.elapsed(at: context.date)
            let fraction = now.duration > 0 ? min(1, elapsed / now.duration) : 0
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule()
                            .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(isHovered ? 8 : 5, geo.size.width * fraction))
                            .shadow(color: tint.opacity(0.6), radius: 4)
                    }
                    .frame(height: isHovered ? 8 : 5)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { point in
                        guard now.canSeek else { return }
                        onSeek(max(0, min(1, point.x / geo.size.width)) * now.duration)
                    }
                }
                .frame(height: 10)
                .onHover { isHovered = $0 && now.canSeek }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)

                HStack {
                    Text(Self.format(elapsed))
                    Spacer()
                    Text(now.duration > 0 ? "-" + Self.format(max(0, now.duration - elapsed)) : "LIVE")
                }
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct PlayButton: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.black)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 40)
                // Solid white, not tinted glass: tinted glass renders too dark for the black icon.
                .background(Circle().fill(.white))
                .shadow(color: .white.opacity(0.2), radius: 8)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

private struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    var enabled = true
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: size + 18, height: size + 18)
                .islandGlass(in: Circle(), tint: .white.opacity(isHovered && enabled ? 0.12 : 0),
                             interactive: enabled)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// The little equalizer shown beside the notch while audio plays.
struct AudioBars: View {
    let isPlaying: Bool
    let color: Color
    var height: CGFloat = 14

    @ObservedObject private var spectrum = LiveSpectrum.shared
    private let speeds: [Double] = [5.1, 6.7, 4.3, 7.4]

    var body: some View {
        if let bands = spectrum.bands, isPlaying {
            HStack(spacing: 2) {
                ForEach(bands.indices, id: \.self) { i in
                    Capsule()
                        .fill(LinearGradient(colors: [color, color.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                        .frame(width: height / 4.5, height: height * CGFloat(0.15 + 0.85 * bands[i]))
                }
            }
            .frame(height: height)
            .animation(.linear(duration: 0.08), value: bands)
        } else {
            decorative
        }
    }

    private var decorative: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<speeds.count, id: \.self) { i in
                    let level = isPlaying ? 0.3 + 0.7 * abs(sin(t * speeds[i] + Double(i) * 1.3)) : 0.2
                    Capsule()
                        .fill(LinearGradient(colors: [color, color.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                        .frame(width: height / 4.5, height: height * level)
                }
            }
            .frame(height: height)
        }
    }
}
