#if DIRECT_DISTRIBUTION
import AppKit
import CoreGraphics

/// Built-in display brightness. Direct-download edition only: macOS has no public API for it,
/// so this uses the private DisplayServices framework, which the App Store doesn't allow.
final class BrightnessService {
    var onChange: ((Float) -> Void)?

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    private let getBrightness: GetBrightness?
    private var timer: Timer?
    private var last: Float?
    /// Auto-brightness drifts in tiny steps; a key press jumps by about 6%.
    private let announceThreshold: Float = 0.03

    init() {
        let framework = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        getBrightness = dlsym(framework, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetBrightness.self) }
        last = level
        // There's no change notification, so check four times a second.
        if getBrightness != nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
        }
    }

    var level: Float? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        return getBrightness(Self.builtInDisplay, &value) == 0 ? value : nil
    }

    private func poll() {
        guard let value = level else { return }
        defer { last = value }
        if let last, abs(value - last) >= announceThreshold { onChange?(value) }
    }

    private static var builtInDisplay: CGDirectDisplayID {
        var displays = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetActiveDisplayList(8, &displays, &count)
        return displays.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) ?? CGMainDisplayID()
    }
}

/// Takes over the volume up and down keys so only the island's pop-up appears, not the system's.
/// Direct edition only, opt-in, and it needs Accessibility permission.
///
/// Every other key goes to macOS untouched: mute, play/pause, and brightness (on macOS 27 the
/// system undoes brightness changes made by apps, so taking those keys over left them stuck).
final class MediaKeyTap {
    enum Key {
        case volumeUp, volumeDown
    }

    /// The key, and whether Option-Shift was held for a fine (quarter) step.
    var onKey: ((Key, Bool) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { tap != nil }
    /// For the status row in Settings.
    private(set) static var isActive = false
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows macOS's own prompt to allow Accessibility in System Settings.
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Tries to take over the keys; safe to call repeatedly. Returns whether it's running.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        // Media keys arrive as "system defined" events; every other key passes straight through.
        guard let tap = makeTap(CGEventMask(1 << 14)) else { return false } // NSEvent.EventType.systemDefined
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        Self.isActive = true
        DiagnosticsLog.write("Volume key takeover on.")
        return true
    }

    private func makeTap(_ mask: CGEventMask) -> CFMachPort? {
        let context = Unmanaged.passUnretained(self).toOpaque()
        return CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let keyTap = Unmanaged<MediaKeyTap>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = keyTap.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                return keyTap.handle(event) ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: context
        )
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        self.tap = nil
        runLoopSource = nil
        Self.isActive = false
        DiagnosticsLog.write("Key takeover off.")
    }

    /// True when the event was one of our keys and should be swallowed (both press and release,
    /// so the system pop-up never shows).
    private func handle(_ cgEvent: CGEvent) -> Bool {
        guard let event = NSEvent(cgEvent: cgEvent), event.subtype.rawValue == 8 else { return false }
        let keyCode = Int((event.data1 & 0xFFFF_0000) >> 16)
        let isDown = (event.data1 & 0xFF00) >> 8 == 0xA
        // NX_KEYTYPE_* values from IOKit's ev_keymap.h: 0 is volume up, 1 volume down.
        let key: Key
        switch keyCode {
        case 0: key = .volumeUp
        case 1: key = .volumeDown
        default:
            if isDown { DiagnosticsLog.write("Media key \(keyCode) passed to macOS.") }
            return false
        }
        if isDown {
            DiagnosticsLog.write("Media key \(keyCode) handled by the island.")
            let fine = event.modifierFlags.contains([.option, .shift])
            onKey?(key, fine)
        }
        return true
    }
}
#endif
