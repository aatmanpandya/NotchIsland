import SwiftUI

extension NotchViewModel.Activity {
    func accent(in vm: NotchViewModel) -> Color {
        switch self {
        case .charging, .fullyCharged: .green
        case .unplugged: .white
        case .lowBattery: vm.battery.isLowPowerMode ? .yellow : .red
        case .nowPlaying: vm.media.tint
        case .call: .green
        case .meetingSoon: vm.soonMeeting?.color ?? .blue
        case .timerDone: .orange
        case .deviceConnected: .blue
        case .volume: .white
        case .brightness: .yellow
        }
    }
}

/// The pop-up shown for a few seconds when something happens.
struct ActivityView: View {
    @ObservedObject var vm: NotchViewModel
    let activity: NotchViewModel.Activity
    let namespace: Namespace.ID

    var body: some View {
        let accent = activity.accent(in: vm)
        VStack(spacing: 0) {
            // Top row, beside the hardware notch. The now-playing pop-up leaves it empty so the
            // artwork and bars below aren't shown twice.
            HStack {
                switch activity {
                case .nowPlaying, .volume, .brightness:
                    EmptyView()
                case .call:
                    Image(systemName: "video.fill").foregroundStyle(accent)
                    Spacer()
                    CallTimer(startedAt: vm.call?.startedAt ?? Date()).foregroundStyle(accent)
                case .timerDone:
                    Image(systemName: "timer").foregroundStyle(accent)
                    Spacer()
                    Text("0:00").foregroundStyle(accent)
                case .deviceConnected:
                    Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(accent)
                    Spacer()
                    if let battery = vm.connectedDevice?.batteryPercent {
                        Text("\(battery)%").foregroundStyle(battery <= 20 ? .red : .green)
                    }
                case .meetingSoon:
                    Image(systemName: "calendar").foregroundStyle(accent)
                    Spacer()
                    if let meeting = vm.soonMeeting {
                        TimelineView(.periodic(from: .now, by: 15)) { context in
                            Text(MeetingTime.countdown(to: meeting, at: context.date)).foregroundStyle(accent)
                        }
                    }
                default:
                    batteryIcon.foregroundStyle(accent)
                    Spacer()
                    Text("\(vm.battery.level)%").foregroundStyle(accent)
                }
            }
            .font(.system(size: 13, weight: .bold).monospacedDigit())
            .frame(height: vm.notchSize.height)
            .padding(.horizontal, vm.topRadius(for: .activity(activity)) + 16)

            HStack(spacing: 14) {
                content(accent: accent)
            }
            .padding(.horizontal, vm.topRadius(for: .activity(activity)) + 18)
            .frame(maxHeight: .infinity)
            .padding(.bottom, 6)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
    }

    @ViewBuilder private var batteryIcon: some View {
        switch activity {
        case .charging, .fullyCharged: Image(systemName: "bolt.fill").symbolEffect(.pulse)
        case .unplugged: Image(systemName: "powerplug.fill")
        case .lowBattery: Image(systemName: "exclamationmark.triangle.fill")
        case .nowPlaying, .call, .meetingSoon, .timerDone, .deviceConnected, .volume, .brightness: EmptyView()
        }
    }

    @ViewBuilder private func content(accent: Color) -> some View {
        switch activity {
        case .nowPlaying:
            let now = vm.media.current
            ArtworkView(image: now?.artwork, size: 40, corner: 10)
                .matchedGeometryEffect(id: IslandMotion.artworkID, in: namespace)
                .shadow(color: accent.opacity(0.5), radius: 8)
            titles(now?.title ?? "Now Playing", now?.artist ?? "")
            Spacer(minLength: 0)
            AudioBars(isPlaying: true, color: accent, height: 20)
                .matchedGeometryEffect(id: IslandMotion.barsID, in: namespace)
        case .call:
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(accent.opacity(0.18)))
            titles("Call started", vm.call?.site ?? "")
            Spacer(minLength: 0)
            LiveBadge(color: accent)
        case .meetingSoon:
            let meeting = vm.soonMeeting
            Image(systemName: meeting?.joinURL == nil ? "calendar" : "video.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(accent.opacity(0.18)))
            titles(meeting?.title ?? "Meeting", meeting.map { "Starts \(MeetingTime.range($0))" } ?? "")
            Spacer(minLength: 0)
            if let url = meeting?.joinURL { JoinButton(url: url, color: accent) }
        case .lowBattery:
            titles(batteryTitle, batterySubtitle)
            Spacer(minLength: 0)
            LowPowerButton(battery: vm.battery)
        case .timerDone:
            Image(systemName: "bell.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(accent.opacity(0.18)))
                .symbolEffect(.pulse)
            titles("Time's up", vm.timer.displayLabel)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                PopUpButton(title: "+1 min", tint: .white.opacity(0.16), foreground: .white) {
                    vm.timer.addMinute()
                    vm.dismissActivity()
                }
                PopUpButton(title: "Dismiss", tint: accent, foreground: .black) { vm.dismissActivity() }
            }
        case .volume, .brightness:
            LevelPopUp(kind: activity, level: vm.hudLevel, muted: vm.hudMuted, device: vm.hudDevice, accent: accent)
        case .deviceConnected:
            let device = vm.connectedDevice
            Image(systemName: device?.symbol ?? "dot.radiowaves.left.and.right")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(accent.opacity(0.25)))
            titles(device?.name ?? "Device", "Connected")
            Spacer(minLength: 0)
            if let battery = device?.batteryPercent {
                LiquidBattery(level: battery, color: battery <= 20 ? .red : .green, isCharging: false)
                    .frame(width: 96, height: 26)
            }
        default:
            titles(batteryTitle, batterySubtitle)
            Spacer(minLength: 0)
            LiquidBattery(level: vm.battery.level, color: accent, isCharging: activity == .charging)
                .frame(width: 128, height: 30)
        }
    }

    private func titles(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
    }

    private var batteryTitle: String {
        switch activity {
        case .charging: "Charging"
        case .unplugged: "On Battery"
        case .fullyCharged: "Fully Charged"
        case .lowBattery: "Low Battery"
        case .nowPlaying, .call, .meetingSoon, .timerDone, .deviceConnected, .volume, .brightness: ""
        }
    }

    private var batterySubtitle: String {
        let battery = vm.battery
        switch activity {
        case .charging: return battery.minutesToFull.map { "Full in \($0.durationText)" } ?? "Power adapter connected"
        case .unplugged: return battery.minutesToEmpty.map { "About \($0.durationText) left" } ?? "Power adapter disconnected"
        case .fullyCharged: return "You can unplug now"
        case .lowBattery: return "\(battery.level)% remaining"
        case .nowPlaying, .call, .meetingSoon, .timerDone, .deviceConnected, .volume, .brightness: return ""
        }
    }
}

/// Volume or brightness: an icon, a bar that follows each press, and the percentage.
private struct LevelPopUp: View {
    let kind: NotchViewModel.Activity
    let level: Float
    let muted: Bool
    let device: String
    let accent: Color

    var body: some View {
        let shown = muted ? 0 : CGFloat(level)
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(accent)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 28)
        VStack(alignment: .leading, spacing: 5) {
            if kind == .volume, !device.isEmpty {
                Text(device)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(accent).frame(width: max(6, geo.size.width * shown))
                }
            }
            .frame(height: 6)
        }
        .animation(.spring(duration: 0.25, bounce: 0.1), value: shown)
        Text(muted ? "Muted" : "\(Int((level * 100).rounded()))%")
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
            .frame(width: 50, alignment: .trailing)
    }

    private var symbol: String {
        if kind == .brightness { return level < 0.5 ? "sun.min.fill" : "sun.max.fill" }
        if muted || level == 0 { return "speaker.slash.fill" }
        let lowered = device.lowercased()
        if lowered.contains("airpods max") { return "airpodsmax" }
        if lowered.contains("airpods pro") { return "airpodspro" }
        if lowered.contains("airpods") { return "airpods" }
        return level < 0.34 ? "speaker.wave.1.fill" : level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }
}

private struct PopUpButton: View {
    let title: String
    let tint: Color
    let foreground: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(tint))
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// Like the iPhone's low-battery alert: one tap toward Low Power Mode, and "On" once it's enabled.
private struct LowPowerButton: View {
    @ObservedObject var battery: BatteryService

    var body: some View {
        Button { battery.openLowPowerSettings() } label: {
            Label(battery.isLowPowerMode ? "Low Power On" : "Low Power Mode",
                  systemImage: battery.isLowPowerMode ? "checkmark" : "leaf.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(.yellow))
                .shadow(color: .yellow.opacity(0.4), radius: 6)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(battery.isLowPowerMode)
        .help("Opens Battery settings, where Low Power Mode is one toggle")
    }
}

/// Time since the call started, ticking every second.
private struct CallTimer: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(startedAt)))
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .contentTransition(.numericText())
        }
    }
}

private struct LiveBadge: View {
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color, radius: 4)
                .phaseAnimator([1.0, 0.35]) { dot, opacity in dot.opacity(opacity) } animation: { _ in
                    .easeInOut(duration: 0.7)
                }
            Text("LIVE")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.15)))
    }
}

/// A wide battery that fills up when it appears, with a moving sheen while charging.
struct LiquidBattery: View {
    let level: Int
    let color: Color
    let isCharging: Bool
    @State private var shown: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let body = geo.size.width - 5
            HStack(spacing: 2) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, (body - 6) * shown))
                        .overlay { if isCharging { Sheen() } }
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: color.opacity(0.6), radius: 8)
                        .padding(3)
                }
                .frame(width: body)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white.opacity(0.25))
                    .frame(width: 3, height: geo.size.height * 0.35)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.75).delay(0.15)) {
                shown = CGFloat(level) / 100
            }
        }
    }
}

private struct Sheen: View {
    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            GeometryReader { geo in
                LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.4)
                    .offset(x: (geo.size.width * 1.4) * phase - geo.size.width * 0.4)
            }
        }
        .blendMode(.plusLighter)
    }
}
