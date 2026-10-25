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

    override init() {
        super.init()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceConnected(_:device:))
        )
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard Date() > quietUntil else { return }
        let info = Device(name: device.name ?? "Bluetooth device",
                          symbol: Self.symbol(for: device),
                          batteryPercent: Self.batteryPercent(of: device))
        DispatchQueue.main.async { [weak self] in self?.onConnect?(info) }
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
