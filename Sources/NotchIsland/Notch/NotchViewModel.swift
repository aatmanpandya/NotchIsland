import AppKit
import Combine

final class NotchViewModel: ObservableObject {
    /// A short-lived pop-up, like a Live Activity on iPhone.
    enum Activity: Equatable {
        case charging
        case unplugged
        case fullyCharged
        case lowBattery
        case nowPlaying
        case call
        case meetingSoon
        case timerDone
        case deviceConnected
    }

    enum Tab: CaseIterable {
        case home
        case shelf
        case tools
    }

    /// What the collapsed island shows beside the notch.
    enum Ears {
        case none
        case media
        case timer
    }

    /// Briefly opens the island so a new user sees where it lives.
    func demo() {
        isExpanded = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.isExpanded = false }
    }

    struct CallInfo {
        let site: String
        let startedAt: Date
    }

    enum Mode: Equatable {
        case collapsed
        case activity(Activity)
        case expanded
    }

    @Published var isExpanded = false {
        // Each time the island opens, it starts on Home.
        didSet { if !isExpanded { tab = .home } }
    }
    @Published var tab: Tab = .home
    /// The device announced by the most recent connection pop-up.
    @Published private(set) var connectedDevice: BluetoothService.Device?
    @Published private(set) var notchSize = CGSize(width: 185, height: 32)
    @Published private(set) var activity: Activity?
    /// The call announced by the most recent call pop-up.
    @Published private(set) var call: CallInfo?
    /// The meeting announced by the most recent meeting pop-up.
    @Published private(set) var soonMeeting: Meeting?
    /// Whether the ears are currently out; they tuck away a few seconds after playback starts.
    @Published private(set) var earsRevealed = false

    let media: MediaController
    let battery: BatteryService
    let calendar: CalendarService
    let timer: TimerService
    let bluetooth: BluetoothService
    let shelf: ShelfService
    let expandedSize = CGSize(width: 640, height: 210)

    private var cancellables = Set<AnyCancellable>()
    private var activityDismissal: DispatchWorkItem?
    private var earsDismissal: DispatchWorkItem?
    private var earsHideAt: Date?
    private let launchedAt = Date()

    init(media: MediaController, battery: BatteryService, calendar: CalendarService,
         timer: TimerService, bluetooth: BluetoothService, shelf: ShelfService) {
        self.media = media
        self.battery = battery
        self.calendar = calendar
        self.timer = timer
        self.bluetooth = bluetooth
        self.shelf = shelf
        timer.onFinish = { [weak self] in self?.show(.timerDone, for: 12) }
        timer.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        bluetooth.onConnect = { [weak self] device in
            self?.connectedDevice = device
            self?.show(.deviceConnected, for: 4)
        }
        calendar.onMeetingSoon = { [weak self] meeting in
            self?.soonMeeting = meeting
            self?.show(.meetingSoon, for: 8)
        }
        // The collapsed size depends on media state, so re-render when it changes.
        media.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)

        battery.onEvent = { [weak self] event in
            switch event {
            case .pluggedIn: self?.show(.charging)
            case .unplugged: self?.show(.unplugged)
            case .fullyCharged: self?.show(.fullyCharged)
            // Longer, so there's time to reach the Low Power Mode button.
            case .low: self?.show(.lowBattery, for: 8)
            }
        }

        // Pop up when a new track starts, but not for whatever was already playing at launch.
        media.$current
            .compactMap { $0 }
            .filter(\.isPlaying)
            .removeDuplicates { $0.sourceID == $1.sourceID && $0.title == $1.title }
            .sink { [weak self] _ in
                guard let self, Date().timeIntervalSince(launchedAt) > 2 else { return }
                if activity == nil || activity == .nowPlaying { show(.nowPlaying, for: 3) }
                revealEars(after: 3)
            }
            .store(in: &cancellables)

        // Starting or resuming playback brings the ears out briefly.
        media.$current
            .map { $0?.isPlaying == true }
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self else { return }
                revealEars()
            }
            .store(in: &cancellables)
    }

    var mode: Mode {
        if isExpanded { return .expanded }
        if let activity { return .activity(activity) }
        return .collapsed
    }

    /// The island grows "ears" beside the notch for a few seconds when playback starts.
    var showsEars: Bool { earsRevealed && media.current?.isPlaying == true }

    /// Music gets the ears first; a running timer takes them when nothing else needs them.
    var ears: Ears {
        if showsEars { return .media }
        return timer.isActive ? .timer : .none
    }

    /// With music in the ears, a timer splits off into its own bubble, as on iPhone.
    var showsTimerBubble: Bool { ears == .media && timer.isActive }
    var earWidth: CGFloat { notchSize.height + 12 }

    func topRadius(for mode: Mode) -> CGFloat {
        switch mode {
        case .collapsed: 6
        case .activity: 12
        case .expanded: 18
        }
    }

    func bottomRadius(for mode: Mode) -> CGFloat {
        switch mode {
        case .collapsed: 12
        case .activity: 26
        case .expanded: 34
        }
    }

    func size(for mode: Mode) -> CGSize {
        switch mode {
        case .expanded:
            return expandedSize
        case .activity:
            return CGSize(width: max(400, notchSize.width + 220), height: notchSize.height + 62)
        case .collapsed:
            let ears = ears == .none ? 0 : earWidth * 2
            return CGSize(width: notchSize.width + ears + topRadius(for: mode) * 2, height: notchSize.height)
        }
    }

    func updateGeometry(for screen: NSScreen) {
        let insetTop = screen.safeAreaInsets.top
        if insetTop > 0,
           let left = screen.auxiliaryTopLeftArea?.width,
           let right = screen.auxiliaryTopRightArea?.width {
            notchSize = CGSize(width: screen.frame.width - left - right, height: insetTop)
        } else {
            // No hardware notch: draw a pill the height of the menu bar.
            notchSize = CGSize(width: 185, height: max(24, screen.frame.maxY - screen.visibleFrame.maxY))
        }
    }

    /// Extends the reveal; a shorter request never cuts an earlier, longer one short.
    /// Announce a call for a few seconds, even over something that is playing.
    func callStarted(site: String) {
        call = CallInfo(site: site, startedAt: Date())
        show(.call, for: 5)
    }

    /// Holds the island in one state for design work and screenshots:
    /// `NOTCHISLAND_PREVIEW=<state> open build/NotchIsland.app`. Returns false for unknown names.
    func pinForPreview(_ name: String) -> Bool {
        let activities: [String: Activity] = [
            "charging": .charging, "unplugged": .unplugged, "full": .fullyCharged,
            "low": .lowBattery, "nowplaying": .nowPlaying, "call": .call, "meeting": .meetingSoon,
            "timerdone": .timerDone, "device": .deviceConnected,
        ]
        if name == "expanded" {
            isExpanded = true
        } else if name == "shelf" {
            // Sample files that aren't saved, so the real shelf stays as it was.
            let pictures = URL(fileURLWithPath: "/System/Library/Desktop Pictures")
            let samples = (try? FileManager.default.contentsOfDirectory(at: pictures, includingPropertiesForKeys: nil))?
                .filter { ["heic", "jpg", "png"].contains($0.pathExtension.lowercased()) }
                .prefix(2) ?? []
            shelf.add(Array(samples) + [Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist")],
                      persist: false)
            isExpanded = true
            tab = .shelf
        } else if name == "dropzone" {
            isExpanded = true
            tab = .shelf
        } else if name == "tools" {
            isExpanded = true
            tab = .tools
        } else if name == "timer" {
            timer.start(seconds: 25 * 60)
        } else if name == "upnext" {
            calendar.useSampleMeetings()
            isExpanded = true
        } else if let pinned = activities[name] {
            if pinned == .call { call = CallInfo(site: "Google Meet", startedAt: Date().addingTimeInterval(-75)) }
            if pinned == .deviceConnected {
                connectedDevice = BluetoothService.Device(name: "AirPods Pro", symbol: "airpodspro", batteryPercent: 82)
            }
            if pinned == .meetingSoon {
                calendar.useSampleMeetings()
                soonMeeting = calendar.next
            }
            activity = pinned
        } else {
            return false
        }
        return true
    }

    /// Brings the ears out for the user's chosen time, plus `extra` seconds. Extends an earlier
    /// reveal but never cuts one short.
    private func revealEars(after extra: TimeInterval = 0) {
        let linger = Preferences.earsLinger
        guard linger != 0 else { return }
        if linger < 0 {
            // "The whole time it plays": showsEars already requires playback.
            earsDismissal?.cancel()
            earsHideAt = .distantFuture
            earsRevealed = true
            return
        }
        let seconds = TimeInterval(linger) + extra
        let hideAt = Date().addingTimeInterval(seconds)
        if earsRevealed, let current = earsHideAt, current > hideAt { return }
        earsHideAt = hideAt
        earsDismissal?.cancel()
        earsRevealed = true
        let work = DispatchWorkItem { [weak self] in self?.earsRevealed = false }
        earsDismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func dismissActivity() {
        activityDismissal?.cancel()
        activity = nil
    }

    private func show(_ activity: Activity, for seconds: TimeInterval = 3.5) {
        guard Preferences.isPopUpEnabled(activity.settingsKey) else { return }
        activityDismissal?.cancel()
        self.activity = activity
        let work = DispatchWorkItem { [weak self] in self?.activity = nil }
        activityDismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

extension NotchViewModel.Activity {
    /// Names the on/off switch for this pop-up in Settings.
    var settingsKey: String {
        switch self {
        case .charging: "charging"
        case .unplugged: "unplugged"
        case .fullyCharged: "fullyCharged"
        case .lowBattery: "lowBattery"
        case .nowPlaying: "nowPlaying"
        case .call: "call"
        case .meetingSoon: "meetingSoon"
        case .timerDone: "timerDone"
        case .deviceConnected: "deviceConnected"
        }
    }
}
