import AppKit
import SwiftUI

/// The app's ordinary windows: Settings and first-run onboarding. The app has no Dock icon,
/// so it brings itself forward while one of them is open.
final class AppWindows {
    static let shared = AppWindows()

    /// Set by `NotchController` once the services exist.
    var calendar: CalendarService?
    var onOnboardingFinished: (() -> Void)?

    private var settings: NSWindow?
    private var onboarding: NSWindow?

    func showSettings() {
        guard let calendar else { return }
        if settings == nil {
            settings = makeWindow(SettingsView(calendar: calendar), title: "NotchIsland Settings")
        }
        present(settings)
    }

    func showOnboarding() {
        guard let calendar else { return }
        if onboarding == nil {
            let view = OnboardingView(calendar: calendar) { [weak self] in self?.finishOnboarding() }
            let window = makeWindow(view, title: "Welcome to NotchIsland")
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            onboarding = window
        }
        present(onboarding)
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: Preferences.Key.hasOnboarded)
        onboarding?.close()
        onboarding = nil
        onOnboardingFinished?()
    }

    private func makeWindow<Content: View>(_ content: Content, title: String) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
