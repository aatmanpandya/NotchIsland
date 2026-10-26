#if DIRECT_DISTRIBUTION && canImport(Sparkle)
import AppKit
import Sparkle

/// Direct-download edition only: finds, verifies and installs new versions with Sparkle. The
/// feed is `appcast.xml` in the repository; every update must be signed with the private key
/// whose public half is `SUPublicEDKey` in the app's Info.plist. The App Store edition is
/// updated by the App Store.
final class Updater: ObservableObject {
    static let shared = Updater()

    private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func checkForUpdates() {
        // The app has no Dock icon, so bring Sparkle's window forward.
        NSApp.activate()
        controller.checkForUpdates(nil)
    }
}
#endif
