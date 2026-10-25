import AppKit
import Combine

final class NotchViewModel: ObservableObject {
    enum Alert: Equatable {
        case charging(Int)
        case unplugged(Int)
    }

    @Published var isExpanded = false
    @Published private(set) var notchSize = CGSize(width: 185, height: 32)
    @Published private(set) var alert: Alert?

    let media: MediaController
    let battery: BatteryService
    let expandedSize = CGSize(width: 620, height: 196)

    private var cancellables = Set<AnyCancellable>()
    private var alertDismissal: DispatchWorkItem?

    init(media: MediaController, battery: BatteryService) {
        self.media = media
        self.battery = battery
        // The collapsed size depends on media state, so re-render when it changes.
        media.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        battery.onPowerChange = { [weak self, weak battery] pluggedIn in
            let level = battery?.level ?? 0
            self?.show(pluggedIn ? .charging(level) : .unplugged(level))
        }
    }

    /// The island grows "ears" beside the notch when it has something live to show.
    var showsEars: Bool { alert != nil || media.current?.isPlaying == true }
    var earWidth: CGFloat { notchSize.height + 12 }

    func topRadius(expanded: Bool) -> CGFloat { expanded ? 18 : 6 }
    func bottomRadius(expanded: Bool) -> CGFloat { expanded ? 32 : 12 }

    func size(expanded: Bool) -> CGSize {
        if expanded { return expandedSize }
        let ears = showsEars ? earWidth * 2 : 0
        return CGSize(width: notchSize.width + ears + topRadius(expanded: false) * 2, height: notchSize.height)
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

    private func show(_ alert: Alert) {
        alertDismissal?.cancel()
        self.alert = alert
        let work = DispatchWorkItem { [weak self] in self?.alert = nil }
        alertDismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }
}
