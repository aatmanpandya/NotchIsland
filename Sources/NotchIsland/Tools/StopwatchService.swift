import Foundation

/// A stopwatch with laps, like the iPhone Clock app's.
final class StopwatchService: ObservableObject {
    /// When the current run started; nil while stopped.
    @Published private(set) var startedAt: Date?
    /// Time from earlier runs before the last stop.
    @Published private(set) var accumulated: TimeInterval = 0
    /// Finished laps, newest first.
    @Published private(set) var laps: [TimeInterval] = []

    private var lapStartedAt: TimeInterval = 0

    var isRunning: Bool { startedAt != nil }
    /// Running, or stopped with time on the clock.
    var hasTime: Bool { isRunning || accumulated > 0 }

    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (startedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    /// The lap in progress.
    func currentLap(at date: Date) -> TimeInterval {
        elapsed(at: date) - lapStartedAt
    }

    func start() {
        guard startedAt == nil else { return }
        startedAt = Date()
    }

    func stop() {
        guard startedAt != nil else { return }
        accumulated = elapsed(at: Date())
        startedAt = nil
    }

    func lap() {
        guard isRunning else { return }
        let now = elapsed(at: Date())
        laps.insert(now - lapStartedAt, at: 0)
        lapStartedAt = now
    }

    func reset() {
        startedAt = nil
        accumulated = 0
        laps.removeAll()
        lapStartedAt = 0
    }
}

extension TimeInterval {
    /// "00:12.34", or "1:02:03.45" past an hour.
    var stopwatchText: String {
        let hundredths = Int((self * 100).rounded(.down))
        let seconds = hundredths / 100
        let fraction = hundredths % 100
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d.%02d", seconds / 3600, seconds / 60 % 60, seconds % 60, fraction)
        }
        return String(format: "%02d:%02d.%02d", seconds / 60, seconds % 60, fraction)
    }
}
