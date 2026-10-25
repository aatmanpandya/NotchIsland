import AppKit
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
    }

    override var canBecomeKey: Bool { false }
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
                                   timer: TimerService(), bluetooth: BluetoothService())
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
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            self?.trackMouse()
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.trackMouse()
            return event
        }) { monitors.append(local) }

        if let preview = ProcessInfo.processInfo.environment["NOTCHISLAND_PREVIEW"]?.lowercased() {
            isPinned = viewModel.pinForPreview(preview)
        }

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
    private func trackMouse() {
        let expanded = viewModel.isExpanded
        let slop: CGFloat = expanded ? 6 : 10
        let inside = islandRect(for: viewModel.mode).insetBy(dx: -slop, dy: -slop)
            .contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside

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

    private func setExpanded(_ expanded: Bool) {
        guard viewModel.isExpanded != expanded else { return }
        if expanded, Preferences.haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        viewModel.isExpanded = expanded
    }
}
