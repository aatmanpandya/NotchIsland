import AppKit
import IOKit.ps

final class BatteryService: ObservableObject {
    enum Event {
        case pluggedIn
        case unplugged
        case fullyCharged
        case low
    }

    @Published private(set) var level = 100
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    @Published private(set) var hasBattery = false
    /// macOS's estimate; nil while it is still calculating.
    @Published private(set) var minutesToFull: Int?
    @Published private(set) var minutesToEmpty: Int?
    @Published private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    var onEvent: ((Event) -> Void)?

    private static let lowThresholds = [20, 10]
    private var runLoopSource: CFRunLoopSource?
    private var powerStateObserver: NSObjectProtocol?

    init() {
        update(notify: false)
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<BatteryService>.fromOpaque(ctx).takeUnretainedValue().update(notify: true)
        }, ctx)?.takeRetainedValue() {
            runLoopSource = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
    }

    private func update(notify: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let cur = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let plugged = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let wasPlugged = isPluggedIn
            let oldLevel = level

            hasBattery = true
            level = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
            isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            isPluggedIn = plugged
            minutesToFull = (desc[kIOPSTimeToFullChargeKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
            minutesToEmpty = (desc[kIOPSTimeToEmptyKey] as? Int).flatMap { $0 > 0 && !plugged ? $0 : nil }

            guard notify else { return }
            if plugged != wasPlugged {
                onEvent?(plugged ? .pluggedIn : .unplugged)
            } else if plugged, level >= 100, oldLevel < 100 {
                onEvent?(.fullyCharged)
            } else if !plugged, Self.lowThresholds.contains(where: { level <= $0 && oldLevel > $0 }) {
                onEvent?(.low)
            }
            return
        }
    }
}

extension BatteryService {
    /// macOS has no public API for apps to switch Low Power Mode on, so this opens Battery
    /// settings, where it is a single toggle.
    func openLowPowerSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension Int {
    /// Minutes as "1h 05m" or "42m".
    var durationText: String {
        self >= 60 ? String(format: "%dh %02dm", self / 60, self % 60) : "\(self)m"
    }
}
