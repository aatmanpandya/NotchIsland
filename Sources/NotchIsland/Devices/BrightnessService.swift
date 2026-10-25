#if DIRECT_DISTRIBUTION
import AppKit
import CoreGraphics

/// Built-in display brightness. Direct-download edition only: macOS has no public API for it,
/// so this uses the private DisplayServices framework, which the App Store doesn't allow.
final class BrightnessService {
    var onChange: ((Float) -> Void)?

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let getBrightness: GetBrightness?
    private let setBrightness: SetBrightness?
    private var timer: Timer?
    private var last: Float?
    /// Auto-brightness drifts in tiny steps; a key press jumps by about 6%.
    private let announceThreshold: Float = 0.03

    init() {
        let framework = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        getBrightness = dlsym(framework, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetBrightness.self) }
        setBrightness = dlsym(framework, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetBrightness.self) }
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

    /// Moves brightness by `delta` (0...1 scale), like the brightness keys.
    func adjust(by delta: Float) {
        guard let setBrightness, let current = level else { return }
        let next = min(1, max(0, current + delta))
        _ = setBrightness(Self.builtInDisplay, next)
        last = next
        onChange?(next)
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

/// Takes over the volume and brightness keys so only the island's pop-up appears, not the
/// system's. Direct edition only, opt-in, and it needs Accessibility permission.
final class MediaKeyTap {
    enum Key {
        case volumeUp, volumeDown, mute, brightnessUp, brightnessDown
    }

    /// The key, and whether Option-Shift was held for a fine (quarter) step.
    var onKey: ((Key, Bool) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { tap != nil }
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows macOS's own prompt to allow Accessibility in System Settings.
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil, Self.isTrusted else { return isRunning }
        // Media keys arrive as "system defined" events. Some Apple keyboards send brightness as
        // ordinary key presses instead (key codes 144 and 145), so watch those too; every other
        // key passes straight through.
        let systemDefined = CGEventMask(1 << 14) // NSEvent.EventType.systemDefined
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: systemDefined,
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
        ) else {
            NSLog("NotchIsland: couldn't create the media key tap")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        NSLog("NotchIsland: media key takeover is on")
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        self.tap = nil
        runLoopSource = nil
    }

    /// True when the event was one of our keys and should be swallowed (both press and release,
    /// so the system pop-up never shows).
    private func handle(_ cgEvent: CGEvent) -> Bool {
        if cgEvent.type == .keyDown || cgEvent.type == .keyUp {
            let code = cgEvent.getIntegerValueField(.keyboardEventKeycode)
            guard code == 144 || code == 145 else { return false }
            NSLog("NotchIsland: brightness key (key code %lld)", code)
            if cgEvent.type == .keyDown {
                let fine = cgEvent.flags.contains([.maskAlternate, .maskShift])
                onKey?(code == 144 ? .brightnessUp : .brightnessDown, fine)
            }
            return true
        }
        guard let event = NSEvent(cgEvent: cgEvent), event.subtype.rawValue == 8 else { return false }
        let keyCode = Int((event.data1 & 0xFFFF_0000) >> 16)
        let isDown = (event.data1 & 0xFF00) >> 8 == 0xA
        // NX_KEYTYPE_* values from IOKit's ev_keymap.h.
        let key: Key
        switch keyCode {
        case 0: key = .volumeUp
        case 1: key = .volumeDown
        case 7: key = .mute
        case 2: key = .brightnessUp
        case 3: key = .brightnessDown
        default: return false
        }
        if key == .brightnessUp || key == .brightnessDown {
            NSLog("NotchIsland: brightness key (media key %d)", keyCode)
        }
        if isDown {
            let fine = event.modifierFlags.contains([.option, .shift])
            onKey?(key, fine)
        }
        return true
    }
}
#endif
