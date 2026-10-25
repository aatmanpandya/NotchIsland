import Foundation

/// User settings, stored in UserDefaults. Views bind to the same keys with `@AppStorage`.
enum Preferences {
    enum Key {
        static let hasOnboarded = "hasOnboarded"
        static let haptics = "haptics"
        /// Seconds the album art stays beside the notch: 0 = never, -1 = the whole time it plays.
        static let earsLinger = "earsLinger"
        static let meetingLeadMinutes = "meetingLeadMinutes"
        static let liveVisualizer = "liveVisualizer"
        /// Direct edition: take over the volume and brightness keys so the system pop-up never shows.
        static let replaceSystemHUD = "replaceSystemHUD"

        static func popUp(_ name: String) -> String { "popUp.\(name)" }
        static func source(_ id: String) -> String { "source.\(id)" }
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.haptics: true,
            Key.earsLinger: 5,
            Key.meetingLeadMinutes: 5,
            Key.liveVisualizer: false,
            Key.replaceSystemHUD: false,
            // The App Store edition can only show its pop-up next to the system's, so it starts off.
            Key.popUp("volume"): isDirectEdition,
            Key.popUp("brightness"): isDirectEdition,
        ])
    }

    /// Every pop-up and media source is on unless the user turned it off.
    static func isPopUpEnabled(_ name: String) -> Bool { flag(Key.popUp(name)) }
    static func isSourceEnabled(_ id: String) -> Bool { flag(Key.source(id)) }

    static var haptics: Bool { UserDefaults.standard.bool(forKey: Key.haptics) }
    static var earsLinger: Int { UserDefaults.standard.integer(forKey: Key.earsLinger) }
    static var meetingLead: TimeInterval {
        TimeInterval(UserDefaults.standard.integer(forKey: Key.meetingLeadMinutes) * 60)
    }

    static var isDirectEdition: Bool {
        #if DIRECT_DISTRIBUTION
        true
        #else
        false
        #endif
    }

    private static func flag(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}
