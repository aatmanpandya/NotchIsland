import Foundation
import IOKit.ps

final class BatteryService: ObservableObject {
    @Published private(set) var level = 100
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    @Published private(set) var hasBattery = false

    /// Called with `true` when power is connected, `false` when disconnected.
    var onPowerChange: ((Bool) -> Void)?

    private var runLoopSource: CFRunLoopSource?

    init() {
        update(notify: false)
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
            hasBattery = true
            level = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
            isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            isPluggedIn = plugged
            if notify && plugged != wasPlugged { onPowerChange?(plugged) }
            return
        }
    }
}
