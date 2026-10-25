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
    @State private var hours = 0
    @State private var minutes = 5
    @State private var seconds = 0
    private let quickPicks = [5, 10, 25]
    private let wheelHeight: CGFloat = 132

    private var total: TimeInterval { TimeInterval(hours * 3600 + minutes * 60 + seconds) }

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
            HStack(spacing: 16) {
                // Like the iPhone Clock app: scroll each wheel, then press Start.
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.1))
                        .frame(height: WheelPicker.rowHeight)
                    HStack(spacing: 4) {
                        WheelPicker(values: 0..<24, selection: $hours, unit: "h", height: wheelHeight)
                        WheelPicker(values: 0..<60, selection: $minutes, unit: "min", height: wheelHeight)
                        WheelPicker(values: 0..<60, selection: $seconds, unit: "sec", height: wheelHeight)
                    }
                }
                .frame(height: wheelHeight)

                VStack(spacing: 12) {
                    Button { timer.start(seconds: total) } label: {
                        Text("Start")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(.orange))
                            .shadow(color: .orange.opacity(0.45), radius: 10)
                    }
                    .buttonStyle(PressScaleStyle())
                    .disabled(total == 0)
                    .opacity(total == 0 ? 0.4 : 1)

                    // Quick picks only set the wheels; nothing starts until Start.
                    HStack(spacing: 4) {
                        ForEach(quickPicks, id: \.self) { pick in
                            Button {
                                withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                                    hours = 0
                                    minutes = pick
                                    seconds = 0
                                }
                            } label: {
                                Text("\(pick)m")
                                    .font(.system(size: 10, weight: .semibold))
                                    .frame(width: 28, height: 20)
                                    .background(Capsule().fill(.white.opacity(minutes == pick && hours == 0 && seconds == 0 ? 0.22 : 0.1)))
                            }
                            .buttonStyle(PressScaleStyle())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// One scrolling wheel of numbers that snaps to a row. Rows tilt, shrink and fade with their
/// distance from the center band, like the iOS picker.
private struct WheelPicker: View {
    let values: Range<Int>
    @Binding var selection: Int
    let unit: String
    let height: CGFloat

    static let rowHeight: CGFloat = 28
    @State private var scrolledID: Int?

    var body: some View {
        HStack(spacing: 2) {
            // Rows are measured against the wheel's own center on screen.
            GeometryReader { wheel in
                let centerY = wheel.frame(in: .global).midY
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(values, id: \.self) { value in
                            Text("\(value)")
                                .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                                .frame(width: 36, height: Self.rowHeight)
                                .visualEffect { [height] content, proxy in
                                    let offset = proxy.frame(in: .global).midY - centerY
                                    let distance = min(1, abs(offset) / (height / 2))
                                    return content
                                        .rotation3DEffect(.degrees(Double(-offset / (height / 2)) * 50),
                                                          axis: (x: 1, y: 0, z: 0))
                                        .scaleEffect(1 - distance * 0.25)
                                        .opacity(1 - distance * 0.75)
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrolledID, anchor: .center)
                // Lets the first and last values reach the center band.
                .contentMargins(.vertical, (height - Self.rowHeight) / 2, for: .scrollContent)
            }
            .frame(width: 36, height: height)
            .onAppear { scrolledID = selection }
            .onChange(of: scrolledID) { _, value in
                if let value, value != selection { selection = value }
            }
            .onChange(of: selection) { _, value in
                if scrolledID != value { withAnimation { scrolledID = value } }
            }
            Text(unit)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 24, alignment: .leading)
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
