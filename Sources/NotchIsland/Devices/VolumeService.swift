import AudioToolbox
import CoreAudio

/// The default output device's volume and mute: watched for changes, and adjustable (for the
/// direct edition's volume keys). Public Core Audio API, so the App Store edition can use it.
final class VolumeService {
    struct Reading: Equatable {
        let level: Float
        let isMuted: Bool
        let deviceName: String
    }

    var onChange: ((Reading) -> Void)?

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var listener: AudioObjectPropertyListenerBlock?
    private var last: Reading?
    /// Switching devices (say, to AirPods) isn't a volume change worth announcing.
    private var quietUntil = Date().addingTimeInterval(2)

    init() {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            self?.attachToDefaultDevice()
        }
        attachToDefaultDevice()
    }

    var current: Reading? { read() }

    /// Moves the volume by `delta` (0...1 scale) and unmutes, like the volume keys.
    func adjust(by delta: Float) {
        guard let reading = read() else { return }
        setFloat(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, min(1, max(0, reading.level + delta)))
        if reading.isMuted { setMute(false) }
    }

    // MARK: - Listening

    private func attachToDefaultDevice() {
        if let listener, deviceID != kAudioObjectUnknown {
            for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
                var address = Self.address(selector)
                AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, listener)
            }
        }
        deviceID = Self.defaultOutputDevice()
        quietUntil = max(quietUntil, Date().addingTimeInterval(0.5))
        last = read()

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.volumeChanged() }
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(deviceID, &address, .main, block)
        }
        listener = block
    }

    private func volumeChanged() {
        guard let reading = read(), reading != last else { return }
        last = reading
        if Date() > quietUntil { onChange?(reading) }
    }

    // MARK: - Core Audio

    private func read() -> Reading? {
        guard deviceID != kAudioObjectUnknown,
              let level = getFloat(kAudioHardwareServiceDeviceProperty_VirtualMainVolume) else { return nil }
        return Reading(level: level, isMuted: getUInt32(kAudioDevicePropertyMute) == 1, deviceName: deviceName())
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func defaultOutputDevice() -> AudioObjectID {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    private func getFloat(_ selector: AudioObjectPropertySelector) -> Float? {
        var address = Self.address(selector)
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func getUInt32(_ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = Self.address(selector)
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func setFloat(_ selector: AudioObjectPropertySelector, _ value: Float) {
        var address = Self.address(selector)
        var value = Float32(value)
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    private func setMute(_ muted: Bool) {
        var address = Self.address(kAudioDevicePropertyMute)
        var value = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private func deviceName() -> String {
        var address = Self.address(kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() else { return "" }
        return value as String
    }
}
