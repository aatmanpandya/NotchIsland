import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        controller = NotchController()
        #if DIRECT_DISTRIBUTION && canImport(Sparkle)
        _ = Updater.shared
        #endif
    }

    /// There's no Dock icon, so opening the app again from Finder or Spotlight shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppWindows.shared.showSettings()
        return false
    }
}

// A helper process that exits mid-write should fail the write, not kill the app.
signal(SIGPIPE, SIG_IGN)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
