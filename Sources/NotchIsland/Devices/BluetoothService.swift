import IOBluetooth

/// Announces Bluetooth devices (AirPods, headphones, keyboards, ...) as they connect.
final class BluetoothService: NSObject {
    struct Device: Equatable {
        let name: String
        let symbol: String
        /// Direct-download edition only; macOS has no public API for it.
        let batteryPercent: Int?
    }

    var onConnect: ((Device) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    /// Registering reports devices that are already connected; those aren't news.
    private let quietUntil = Date().addingTimeInterval(3)
    /// When each device was last announced, by address. Links that drop and come back within
    /// `repeatWindow` aren't announced again.
    private var lastAnnounced: [String: Date] = [:]
    static let repeatWindow: TimeInterval = 5 * 60

    override init() {
        super.init()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceConnected(_:device:))
        )
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? "Bluetooth device"
        let address = device.addressString ?? name
        let now = Date()
        let announce = now > quietUntil
            && Self.isAccessory(majorClass: device.deviceClassMajor, name: name)
            && Self.isNews(lastAnnounced: lastAnnounced[address], now: now)
        DiagnosticsLog.write("Bluetooth connect: \(name) (class \(device.deviceClassMajor)), \(announce ? "shown" : "skipped").")
        guard announce else { return }
        lastAnnounced[address] = now
        let info = Device(name: name, symbol: Self.symbol(for: device), batteryPercent: Self.batteryPercent(of: device))
        DispatchQueue.main.async { [weak self] in self?.onConnect?(info) }
    }

    /// Only things the user connects on purpose: headphones, keyboards, mice, controllers.
    /// iPhones, iPads and Macs keep short Bluetooth links open for Handoff, Universal Clipboard
    /// and Instant Hotspot, connecting over and over in the background; announcing those read
    /// like a network alert.
    static func isAccessory(majorClass: BluetoothDeviceClassMajor, name: String) -> Bool {
        let lowered = name.lowercased()
        if ["iphone", "ipad", "macbook", "imac", "mac mini", "mac studio", "mac pro"].contains(where: lowered.contains) {
            return false
        }
        return majorClass != UInt32(kBluetoothDeviceClassMajorPhone)
            && majorClass != UInt32(kBluetoothDeviceClassMajorComputer)
    }

    /// A device that dropped and reconnected a moment ago isn't news.
    static func isNews(lastAnnounced: Date?, now: Date) -> Bool {
        guard let lastAnnounced else { return true }
        return now.timeIntervalSince(lastAnnounced) > repeatWindow
    }

    private static func symbol(for device: IOBluetoothDevice) -> String {
        let name = (device.name ?? "").lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("beats") { return "beats.headphones" }
        switch device.deviceClassMajor {
        case UInt32(kBluetoothDeviceClassMajorAudio): return "headphones"
        case UInt32(kBluetoothDeviceClassMajorPeripheral):
            if name.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
            return name.contains("mouse") ? "magicmouse" : "keyboard"
        case UInt32(kBluetoothDeviceClassMajorPhone): return "iphone"
        default: return "dot.radiowaves.left.and.right"
        }
    }

    private static func batteryPercent(of device: IOBluetoothDevice) -> Int? {
        #if DIRECT_DISTRIBUTION
        // Private IOBluetoothDevice accessors. AirPods report each bud; take the lower one.
        let readings = ["batteryPercentSingle", "batteryPercentLeft", "batteryPercentRight"]
            .compactMap { privateByte(named: $0, of: device) }
            .filter { $0 > 0 }
        return readings.min()
        #else
        return nil
        #endif
    }

    #if DIRECT_DISTRIBUTION
    private static func privateByte(named name: String, of device: IOBluetoothDevice) -> Int? {
        let selector = NSSelectorFromString(name)
        guard device.responds(to: selector), let method = device.method(for: selector) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> UInt8
        return Int(unsafeBitCast(method, to: Getter.self)(device, selector))
    }
    #endif
}
