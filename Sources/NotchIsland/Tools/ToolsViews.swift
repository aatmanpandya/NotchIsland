import AVFoundation
import SwiftUI

/// The Tools tab: timer or stopwatch on the left, the camera mirror on the right.
struct ToolsPanel: View {
    @ObservedObject var timer: TimerService
    @ObservedObject var stopwatch: StopwatchService
    @AppStorage("toolsClockMode") private var mode: ClockMode = .timer

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                ClockModePicker(mode: $mode)
                Group {
                    switch mode {
                    case .timer: TimerPanel(timer: timer)
                    case .stopwatch: StopwatchPanel(stopwatch: stopwatch)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.animation(.easeOut(duration: 0.15)))
                .id(mode)
            }
            LinearGradient(colors: [.clear, .white.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom)
                .frame(width: 1)
            MirrorPanel()
                .frame(width: 180)
        }
    }
}

enum ClockMode: String, CaseIterable {
    case timer
    case stopwatch

    var title: String { self == .timer ? "Timer" : "Stopwatch" }
}

/// A small segmented switch, like the one in the iOS Clock app.
private struct ClockModePicker: View {
    @Binding var mode: ClockMode
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ClockMode.allCases, id: \.self) { option in
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0.2)) { mode = option }
                } label: {
                    Text(option.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(mode == option ? 1 : 0.55))
                        .padding(.horizontal, 10)
                        .frame(height: 20)
                        .background {
                            if mode == option {
                                Capsule().fill(.white.opacity(0.18))
                                    .matchedGeometryEffect(id: "segment", in: selection)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.07)))
    }
}

// MARK: - Timer

/// Laid out like the iPhone Clock app: cancel on the left, wheels in the middle, start on the
/// right, then Label and Sound.
private struct TimerPanel: View {
    @ObservedObject var timer: TimerService
    @State private var hours = 0
    @State private var minutes = 5
    @State private var seconds = 0
    private let wheelHeight: CGFloat = 84

    private var total: TimeInterval { TimeInterval(hours * 3600 + minutes * 60 + seconds) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                // Before a timer runs, ✕ clears the wheels; while one runs, it cancels it.
                ClockButton(symbol: "xmark", style: .gray) {
                    if timer.isActive {
                        timer.cancel()
                    } else {
                        withAnimation(.spring(duration: 0.4, bounce: 0.2)) { hours = 0; minutes = 0; seconds = 0 }
                    }
                }
                .disabled(!timer.isActive && total == 0)
                Spacer(minLength: 6)
                if timer.isActive {
                    countdown
                } else {
                    wheels
                }
                Spacer(minLength: 6)
                if timer.isActive {
                    ClockButton(symbol: timer.isRunning ? "pause.fill" : "play.fill", style: .orange) {
                        timer.isRunning ? timer.pause() : timer.resume()
                    }
                } else {
                    ClockButton(symbol: "play.fill", style: .green) { timer.start(seconds: total) }
                        .disabled(total == 0)
                }
            }
            .frame(height: wheelHeight)

            HStack(spacing: 6) {
                SettingRow(title: "Label") {
                    TextField("Timer", text: $timer.label)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.white.opacity(0.6))
                }
                SettingRow(title: "Sound") {
                    Menu {
                        ForEach(TimerService.sounds, id: \.self) { name in
                            Button(name) {
                                timer.soundName = name
                                timer.previewSound(name)
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(timer.soundName)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(.white.opacity(0.6))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }
        }
    }

    private var wheels: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.white.opacity(0.1))
                .frame(height: WheelPicker.rowHeight)
            HStack(spacing: 2) {
                WheelPicker(values: 0..<24, selection: $hours, unit: "hours", height: wheelHeight)
                WheelPicker(values: 0..<60, selection: $minutes, unit: "min", height: wheelHeight)
                WheelPicker(values: 0..<60, selection: $seconds, unit: "sec", height: wheelHeight)
            }
        }
        .frame(width: 214)
    }

    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            ZStack {
                TimerRing(progress: timer.progress(at: context.date), lineWidth: 5)
                VStack(spacing: 0) {
                    Text(timer.remaining(at: context.date).clockText)
                        .font(.system(size: 19, weight: .regular).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                    Text(timer.displayLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .frame(maxWidth: 60)
                }
            }
            .frame(width: wheelHeight, height: wheelHeight)
        }
    }
}

/// One scrolling wheel of numbers that snaps to a row. Rows tilt, shrink and fade with their
/// distance from the center band, like the iOS picker. The unit sits beside the band.
private struct WheelPicker: View {
    let values: Range<Int>
    @Binding var selection: Int
    let unit: String
    let height: CGFloat

    static let rowHeight: CGFloat = 26
    @State private var scrolledID: Int?

    var body: some View {
        HStack(spacing: 4) {
            // Rows are measured against the wheel's own center on screen.
            GeometryReader { wheel in
                let centerY = wheel.frame(in: .global).midY
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(values, id: \.self) { value in
                            Text("\(value)")
                                .font(.system(size: 19, weight: .regular).monospacedDigit())
                                .frame(width: 28, height: Self.rowHeight, alignment: .trailing)
                                .visualEffect { [height] content, proxy in
                                    let offset = proxy.frame(in: .global).midY - centerY
                                    let distance = min(1, abs(offset) / (height / 2))
                                    return content
                                        .rotation3DEffect(.degrees(Double(-offset / (height / 2)) * 50),
                                                          axis: (x: 1, y: 0, z: 0))
                                        .scaleEffect(1 - distance * 0.2)
                                        .opacity(1 - distance * 0.7)
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
            .frame(width: 28, height: height)
            .onAppear { scrolledID = selection }
            .onChange(of: scrolledID) { _, value in
                if let value, value != selection { selection = value }
            }
            .onChange(of: selection) { _, value in
                if scrolledID != value { withAnimation { scrolledID = value } }
            }
            Text(unit)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 38, alignment: .leading)
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

/// Round buttons in the iOS Clock style: gray, green start, orange pause, red stop.
private struct ClockButton: View {
    enum Style {
        case gray, green, orange, red

        var fill: Color {
            switch self {
            case .gray: .white.opacity(0.14)
            case .green: Color(red: 0.12, green: 0.33, blue: 0.16)
            case .orange: Color(red: 0.36, green: 0.22, blue: 0.05)
            case .red: Color(red: 0.36, green: 0.1, blue: 0.09)
            }
        }

        var foreground: Color {
            switch self {
            case .gray: .white
            case .green: Color(red: 0.2, green: 0.85, blue: 0.35)
            case .orange: .orange
            case .red: Color(red: 1, green: 0.27, blue: 0.23)
            }
        }
    }

    var symbol: String?
    var title: String?
    let style: Style
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                } else if let title {
                    Text(title).font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(style.foreground)
            .frame(width: 46, height: 46)
            .background(Circle().fill(style.fill))
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// An iOS-style grouped row: a title on the left, its value on the right.
private struct SettingRow<Value: View>: View {
    let title: String
    @ViewBuilder let value: Value

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer(minLength: 4)
            value
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.08)))
    }
}

/// Small timer shown in the collapsed island's ears.
struct TimerTicker: View {
    @ObservedObject var timer: TimerService
    let showsTime: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            if showsTime {
                Text(timer.remaining(at: context.date).clockText)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
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

/// A running stopwatch in the collapsed island's ears.
struct StopwatchTicker: View {
    @ObservedObject var stopwatch: StopwatchService
    let showsTime: Bool

    var body: some View {
        if showsTime {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                Text(stopwatch.elapsed(at: context.date).clockText)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        } else {
            Image(systemName: "stopwatch.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
        }
    }
}

/// Beside the island while music has the ears, like the iPhone's split Dynamic Island.
struct TimerBubble: View {
    @ObservedObject var timer: TimerService
    @ObservedObject var stopwatch: StopwatchService
    let size: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            Group {
                if timer.isActive {
                    TimerRing(progress: timer.progress(at: context.date), lineWidth: 2.5)
                        .frame(width: size * 0.52, height: size * 0.52)
                } else {
                    Image(systemName: "stopwatch.fill")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: size, height: size)
            .background(Circle().fill(.black))
        }
    }
}

// MARK: - Stopwatch

private struct StopwatchPanel: View {
    @ObservedObject var stopwatch: StopwatchService

    var body: some View {
        HStack(spacing: 0) {
            // As on iOS: Lap while running, Reset once stopped.
            if stopwatch.isRunning || !stopwatch.hasTime {
                ClockButton(title: "Lap", style: .gray) { stopwatch.lap() }
                    .disabled(!stopwatch.isRunning)
            } else {
                ClockButton(title: "Reset", style: .gray) { stopwatch.reset() }
            }
            Spacer(minLength: 6)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !stopwatch.isRunning)) { context in
                VStack(spacing: 6) {
                    Text(stopwatch.elapsed(at: context.date).stopwatchText)
                        .font(.system(size: 34, weight: .light).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    // Laps appear once it's running, so a fresh stopwatch stays centered.
                    if stopwatch.hasTime {
                        VStack(spacing: 2) {
                            lapRow(stopwatch.laps.count + 1, stopwatch.currentLap(at: context.date))
                            ForEach(Array(stopwatch.laps.prefix(2).enumerated()), id: \.offset) { index, lap in
                                lapRow(stopwatch.laps.count - index, lap)
                            }
                        }
                        .frame(height: 40, alignment: .top)
                    }
                }
            }
            Spacer(minLength: 6)
            if stopwatch.isRunning {
                ClockButton(title: "Stop", style: .red) { stopwatch.stop() }
            } else {
                ClockButton(title: "Start", style: .green) { stopwatch.start() }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func lapRow(_ number: Int, _ time: TimeInterval) -> some View {
        HStack {
            Text("Lap \(number)")
            Spacer()
            Text(time.stopwatchText).monospacedDigit()
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.white.opacity(0.6))
        .frame(width: 150)
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
