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
    }

    enum Mode: Equatable {
        case collapsed
        case activity(Activity)
        case expanded
    }

    @Published var isExpanded = false
    @Published private(set) var notchSize = CGSize(width: 185, height: 32)
    @Published private(set) var activity: Activity?

    let media: MediaController
    let battery: BatteryService
    let expandedSize = CGSize(width: 640, height: 210)

    private var cancellables = Set<AnyCancellable>()
    private var activityDismissal: DispatchWorkItem?
    private let launchedAt = Date()

    init(media: MediaController, battery: BatteryService) {
        self.media = media
        self.battery = battery
        // The collapsed size depends on media state, so re-render when it changes.
        media.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)

        battery.onEvent = { [weak self] event in
            switch event {
            case .pluggedIn: self?.show(.charging)
            case .unplugged: self?.show(.unplugged)
            case .fullyCharged: self?.show(.fullyCharged)
            case .low: self?.show(.lowBattery, for: 5)
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
            }
            .store(in: &cancellables)
    }

    var mode: Mode {
        if isExpanded { return .expanded }
        if let activity { return .activity(activity) }
        return .collapsed
    }

    /// The island grows "ears" beside the notch while something plays.
    var showsEars: Bool { media.current?.isPlaying == true }
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
            let ears = showsEars ? earWidth * 2 : 0
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

    private func show(_ activity: Activity, for seconds: TimeInterval = 3.5) {
        activityDismissal?.cancel()
        self.activity = activity
        let work = DispatchWorkItem { [weak self] in self?.activity = nil }
        activityDismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
