import AVFoundation
import SwiftUI

/// The Tools tab: a timer on the left, the camera mirror on the right.
struct ToolsPanel: View {
    @ObservedObject var timer: TimerService

    var body: some View {
        HStack(spacing: 20) {
            TimerPanel(timer: timer)
            LinearGradient(colors: [.clear, .white.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom)
                .frame(width: 1)
            MirrorPanel()
                .frame(width: 200)
        }
    }
}

// MARK: - Timer

private struct TimerPanel: View {
    @ObservedObject var timer: TimerService
    private let presets: [Int] = [1, 5, 10, 25]

    var body: some View {
        if timer.isActive {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                HStack(spacing: 18) {
                    ZStack {
                        TimerRing(progress: timer.progress(at: context.date), lineWidth: 7)
                        Text(timer.remaining(at: context.date).clockText)
                            .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText(countsDown: true))
                    }
                    .frame(width: 104, height: 104)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(timer.isRunning ? "Timer" : "Paused")
                            .font(.system(size: 15, weight: .semibold))
                        HStack(spacing: 10) {
                            RoundIconButton(symbol: timer.isRunning ? "pause.fill" : "play.fill", tint: .orange) {
                                timer.isRunning ? timer.pause() : timer.resume()
                            }
                            RoundIconButton(symbol: "plus", label: "1", tint: .white) { timer.addMinute() }
                            RoundIconButton(symbol: "xmark", tint: .white) { timer.cancel() }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label("Timer", systemImage: "timer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { minutes in
                        Button { timer.start(seconds: TimeInterval(minutes * 60)) } label: {
                            VStack(spacing: 0) {
                                Text("\(minutes)")
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                Text("min")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .frame(width: 58, height: 52)
                            .islandGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                }
                Text("The countdown stays in the notch while it runs.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

struct TimerRing: View {
    let progress: Double
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(.orange.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, 1 - progress))
                .stroke(.orange, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private struct RoundIconButton: View {
    let symbol: String
    var label: String?
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 1) {
                Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                if let label { Text(label).font(.system(size: 13, weight: .bold, design: .rounded)) }
            }
            .foregroundStyle(tint == .white ? .white : .black)
            .frame(width: 40, height: 40)
            .background(Circle().fill(tint == .white ? Color.white.opacity(0.14) : tint))
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// Small timer shown in the collapsed island: in the ears, or in its own bubble.
struct TimerTicker: View {
    @ObservedObject var timer: TimerService
    let showsTime: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            if showsTime {
                Text(timer.remaining(at: context.date).clockText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText(countsDown: true))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                TimerRing(progress: timer.progress(at: context.date), lineWidth: 2.5)
                    .frame(width: 16, height: 16)
            }
        }
    }
}

/// Beside the island while music has the ears, like the iPhone's split Dynamic Island.
struct TimerBubble: View {
    @ObservedObject var timer: TimerService
    let size: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            TimerRing(progress: timer.progress(at: context.date), lineWidth: 2.5)
                .frame(width: size * 0.52, height: size * 0.52)
                .frame(width: size, height: size)
                .background(Circle().fill(.black))
        }
    }
}

// MARK: - Mirror

private struct MirrorPanel: View {
    @State private var isOn = false
    @State private var access = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.06))
            if isOn, access == .authorized {
                CameraPreview()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button { isOn = false } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(.black.opacity(0.5)))
                        }
                        .buttonStyle(PressScaleStyle())
                        .padding(8)
                    }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.square")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.5))
                    if access == .denied || access == .restricted {
                        Text("Camera access is off")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                    } else {
                        Button("Check your look") { turnOn() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .islandGlass(in: Capsule(), interactive: true)
                    }
                }
            }
        }
    }

    /// Asks for the camera the first time; the camera runs only while the preview is on screen.
    private func turnOn() {
        if access == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    access = AVCaptureDevice.authorizationStatus(for: .video)
                    isOn = granted
                }
            }
        } else {
            isOn = true
        }
    }
}

/// The front camera, mirrored like a real mirror. The session stops when the view goes away.
private struct CameraPreview: NSViewRepresentable {
    final class Coordinator {
        let session = AVCaptureSession()
        let queue = DispatchQueue(label: "notchisland.camera")
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let session = context.coordinator.session
        session.sessionPreset = .medium
        if let camera = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(input) {
            session.addInput(input)
        }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        view.layer = layer
        context.coordinator.queue.async { session.startRunning() }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.queue.async { coordinator.session.stopRunning() }
    }
}
