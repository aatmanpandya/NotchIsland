import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// A borderless panel that sits over the notch, above the menu bar, on every Space.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        // Clicks don't steal focus from other apps, except on a text field (the timer label).
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click land on a button even though the panel never becomes key.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchController {
    let viewModel: NotchViewModel
    private let panel = NotchPanel()
    private var screen: NSScreen?
    private var monitors: [Any] = []
    private var pendingToggle: DispatchWorkItem?
    /// Set by preview mode, so hovering doesn't change the pinned state.
    private var isPinned = false
    private var holdObserver: AnyCancellable?

    // Opening from the keyboard (⌃⌥⌘N) makes the island the active window, so VoiceOver and
    // Tab can reach it; Esc, the shortcut again, or clicking elsewhere closes it.
    private var shortcut: GlobalShortcut?
    private var isKeyboardSession = false
    private var appBeforeKeyboardSession: NSRunningApplication?
    private var keyboardMonitors: [Any] = []

    // Spotting a file being dragged from another app: the drag pasteboard changes after the
    // mouse goes down, and it holds file URLs.
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var dragChangeCount = 0
    private var isDraggingFile = false

    private let volume = VolumeService()
    #if DIRECT_DISTRIBUTION
    private let brightness = BrightnessService()
    private let mediaKeys = MediaKeyTap()
    private var trustCheck: Timer?
    #endif

    init() {
        // Order is priority when several are playing: the dedicated sources give richer
        // controls, and the system-wide source covers every other app.
        let browser = BrowserBridgeSource()
        var sources: [MediaSource] = [
            browser,
            ScriptableAppSource(.spotify),
            ScriptableAppSource(.music),
        ]
        #if DIRECT_DISTRIBUTION
        if let system = SystemNowPlayingSource() { sources.append(system) }
        #endif
        let media = MediaController(sources: sources)
        viewModel = NotchViewModel(media: media, battery: BatteryService(), calendar: CalendarService(),
                                   timer: TimerService(), stopwatch: StopwatchService(),
                                   bluetooth: BluetoothService(), shelf: ShelfService())
        browser.onCallStarted = { [weak viewModel] site in viewModel?.callStarted(site: site) }

        let host = FirstMouseHostingView(rootView: NotchView(vm: viewModel))
        host.sizingOptions = []
        panel.contentView = host
        layout()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.layout() }

        // Mouse-moved monitoring needs no Accessibility permission.
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.handle(event)
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) { monitors.append(local) }

        if let preview = ProcessInfo.processInfo.environment["NOTCHISLAND_PREVIEW"]?.lowercased() {
            isPinned = viewModel.pinForPreview(preview)
        }

        volume.onChange = { [weak viewModel] reading in
            viewModel?.showVolume(level: reading.level, muted: reading.isMuted, device: reading.deviceName)
        }
        #if DIRECT_DISTRIBUTION
        brightness.onChange = { [weak viewModel] level in viewModel?.showBrightness(level) }
        mediaKeys.onKey = { [weak self] key, fine in self?.handleMediaKey(key, fine: fine) }
        updateKeyTakeover()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateKeyTakeover() }
        #endif

        // Once a permission prompt is answered, close the island if the mouse has moved away.
        holdObserver = viewModel.$isHeldOpen.dropFirst().filter { !$0 }
            .sink { [weak self] _ in DispatchQueue.main.async { self?.trackMouse() } }

        shortcut = GlobalShortcut(keyCode: kVK_ANSI_N, modifiers: controlKey | optionKey | cmdKey) { [weak self] in
            self?.toggleKeyboardSession()
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            // Clicking another app ends the session; that app already has focus.
            if self?.isKeyboardSession == true { self?.endKeyboardSession(restoreFocus: false) }
        }
        panel.setAccessibilityLabel("NotchIsland")

        AppWindows.shared.calendar = viewModel.calendar
        AppWindows.shared.onOnboardingFinished = { [weak viewModel] in viewModel?.demo() }
        if !isPinned, !UserDefaults.standard.bool(forKey: Preferences.Key.hasOnboarded) {
            AppWindows.shared.showOnboarding()
        }
    }

    /// Prefer the built-in display with a notch; fall back to the main screen.
    private func layout() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main ?? NSScreen.screens.first else { return }
        self.screen = screen
        viewModel.updateGeometry(for: screen)

        // The panel is sized for the expanded island plus shadow room and never resizes;
        // SwiftUI animates the shape inside it.
        let width = viewModel.expandedSize.width + 80
        let height = viewModel.expandedSize.height + 60
        panel.setFrame(NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height,
                              width: width, height: height), display: true)
    }

    private func islandRect(for mode: NotchViewModel.Mode) -> NSRect {
        guard let screen else { return .zero }
        let size = viewModel.size(for: mode)
        // The timer bubble sits to the right of the collapsed island and is clickable too.
        let bubble = mode == .collapsed && viewModel.showsTimerBubble ? viewModel.notchSize.height + 6 : 0
        return NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                      width: size.width + bubble, height: size.height)
    }

    /// Clicks pass through the transparent panel except over the island itself.
    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragChangeCount = dragPasteboard.changeCount
            isDraggingFile = false
        case .leftMouseDragged where !isDraggingFile:
            isDraggingFile = dragPasteboard.changeCount != dragChangeCount
                && dragPasteboard.canReadObject(forClasses: [NSURL.self],
                                                options: [.urlReadingFileURLsOnly: true])
        case .leftMouseUp:
            isDraggingFile = false
        default:
            break
        }
        trackMouse()
    }

    /// A file dragged near the notch opens the island straight onto the shelf.
    private func openShelfForDrag() {
        panel.ignoresMouseEvents = false
        pendingToggle?.cancel()
        pendingToggle = nil
        viewModel.tab = .shelf
        setExpanded(true)
        viewModel.tab = .shelf
    }

    private func trackMouse() {
        let expanded = viewModel.isExpanded
        let slop: CGFloat = expanded ? 6 : 10
        let mouse = NSEvent.mouseLocation
        if isDraggingFile, !expanded, !isPinned,
           islandRect(for: .collapsed).insetBy(dx: -90, dy: -40).contains(mouse) {
            openShelfForDrag()
            return
        }
        let inside = islandRect(for: viewModel.mode).insetBy(dx: -slop, dy: -slop).contains(mouse)
        panel.ignoresMouseEvents = !inside

        // Opened from the keyboard: stays open and clickable wherever the mouse is.
        if isKeyboardSession {
            panel.ignoresMouseEvents = false
            pendingToggle?.cancel()
            pendingToggle = nil
            return
        }

        // While a permission prompt is up, the open island waits for the answer.
        if expanded, viewModel.isHeldOpen {
            pendingToggle?.cancel()
            pendingToggle = nil
            return
        }

        // A pop-up with buttons (Dismiss, Join, Low Power Mode) stays a pop-up under the cursor,
        // so the click reaches its buttons instead of opening the full panel.
        if inside, !expanded, viewModel.activityIsInteractive {
            pendingToggle?.cancel()
            pendingToggle = nil
            return
        }

        guard !isPinned, inside != expanded else {
            pendingToggle?.cancel()
            pendingToggle = nil
            return
        }
        guard pendingToggle == nil else { return }

        // A short delay on open avoids flicker when the cursor passes by; a longer one on
        // close forgives brief exits.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            pendingToggle = nil
            setExpanded(inside)
        }
        pendingToggle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.1 : 0.25), execute: work)
    }

    #if DIRECT_DISTRIBUTION
    /// Takes over the volume and brightness keys while the setting is on. macOS needs
    /// Accessibility permission for that; until it's granted, ask once and keep checking.
    private func updateKeyTakeover() {
        let wanted = UserDefaults.standard.bool(forKey: Preferences.Key.replaceSystemHUD)
        guard wanted else {
            mediaKeys.stop()
            trustCheck?.invalidate()
            trustCheck = nil
            return
        }
        if mediaKeys.start() { return }
        guard trustCheck == nil else { return }
        DiagnosticsLog.write("Key takeover waiting. Accessibility allowed: \(MediaKeyTap.isTrusted).")
        if !MediaKeyTap.isTrusted { MediaKeyTap.requestTrust() }
        // Keep trying: permission can take effect a moment after it's granted.
        trustCheck = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, mediaKeys.start() else { return }
            timer.invalidate()
            trustCheck = nil
        }
    }

    /// The same steps as macOS: a sixteenth per press, a quarter of that with Option-Shift.
    private func handleMediaKey(_ key: MediaKeyTap.Key, fine: Bool) {
        let step: Float = fine ? 1 / 64 : 1 / 16
        volume.adjust(by: key == .volumeUp ? step : -step)
        // Shown here too, so a press at 0% or 100% (no change to report) still shows the bar.
        if let reading = volume.current {
            viewModel.showVolume(level: reading.level, muted: reading.isMuted, device: reading.deviceName)
        }
    }
    #endif

    private func toggleKeyboardSession() {
        isKeyboardSession ? endKeyboardSession(restoreFocus: true) : startKeyboardSession()
    }

    private func startKeyboardSession() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        appBeforeKeyboardSession = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
        isKeyboardSession = true
        pendingToggle?.cancel()
        pendingToggle = nil
        panel.ignoresMouseEvents = false
        setExpanded(true)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        NSAccessibility.post(element: panel, notification: .focusedWindowChanged)

        if let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape), self?.isKeyboardSession == true else { return event }
            self?.endKeyboardSession(restoreFocus: true)
            return nil
        }) { keyboardMonitors.append(escape) }
    }

    private func endKeyboardSession(restoreFocus: Bool) {
        guard isKeyboardSession else { return }
        isKeyboardSession = false
        keyboardMonitors.forEach(NSEvent.removeMonitor)
        keyboardMonitors.removeAll()
        setExpanded(false)
        if restoreFocus { appBeforeKeyboardSession?.activate() }
        appBeforeKeyboardSession = nil
        trackMouse()
    }

    private func setExpanded(_ expanded: Bool) {
        guard viewModel.isExpanded != expanded else { return }
        if expanded, Preferences.haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        viewModel.isExpanded = expanded
    }
}
