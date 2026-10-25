import AppKit

/// One countdown timer, kept across app restarts.
final class TimerService: ObservableObject {
    /// When a running timer ends.
    @Published private(set) var endDate: Date?
    /// Time left on a paused timer.
    @Published private(set) var pausedRemaining: TimeInterval?
    /// The length the timer was set to, for the progress ring.
    @Published private(set) var duration: TimeInterval = 0
    /// Shown while it runs and when it finishes, like the iPhone's timer label.
    @Published var label: String {
        didSet { UserDefaults.standard.set(label, forKey: Key.label) }
    }
    /// One of the Mac's alert sounds (`sounds`).
    @Published var soundName: String {
        didSet { UserDefaults.standard.set(soundName, forKey: Key.sound) }
    }

    var onFinish: (() -> Void)?

    /// The alert sounds that come with macOS.
    static let sounds: [String] = {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        let found = names.filter { $0.hasSuffix(".aiff") }.map { String($0.dropLast(5)) }.sorted()
        return found.isEmpty ? ["Glass"] : found
    }()

    private enum Key {
        static let end = "timer.end"
        static let paused = "timer.paused"
        static let duration = "timer.duration"
        static let label = "timer.label"
        static let sound = "timer.sound"
    }

    private var finishTimer: Timer?

    init() {
        label = UserDefaults.standard.string(forKey: Key.label) ?? ""
        soundName = UserDefaults.standard.string(forKey: Key.sound) ?? "Glass"
        restore()
    }

    /// The label to show, falling back to "Timer" when none is set.
    var displayLabel: String { label.trimmingCharacters(in: .whitespaces).isEmpty ? "Timer" : label }

    func previewSound(_ name: String) {
        NSSound(named: name)?.play()
    }

    var isActive: Bool { endDate != nil || pausedRemaining != nil }
    var isRunning: Bool { endDate != nil }

    func remaining(at date: Date) -> TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(date)) }
        return pausedRemaining ?? 0
    }

    /// 0 at the start, 1 when time is up.
    func progress(at date: Date) -> Double {
        duration > 0 ? 1 - remaining(at: date) / duration : 0
    }

    func start(seconds: TimeInterval) {
        duration = seconds
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(seconds)
        scheduleFinish()
        save()
    }

    func pause() {
        guard let endDate else { return }
        pausedRemaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        finishTimer?.invalidate()
        save()
    }

    func resume() {
        guard let pausedRemaining else { return }
        self.pausedRemaining = nil
        endDate = Date().addingTimeInterval(pausedRemaining)
        scheduleFinish()
        save()
    }

    /// Adds a minute to a running or paused timer, or starts a one-minute timer if none is set.
    func addMinute() {
        if let endDate {
            self.endDate = endDate.addingTimeInterval(60)
            duration += 60
            scheduleFinish()
            save()
        } else if let pausedRemaining {
            self.pausedRemaining = pausedRemaining + 60
            duration += 60
            save()
        } else {
            start(seconds: 60)
        }
    }

    func cancel() {
        finishTimer?.invalidate()
        endDate = nil
        pausedRemaining = nil
        duration = 0
        save()
    }

    private func scheduleFinish() {
        finishTimer?.invalidate()
        guard let endDate else { return }
        let timer = Timer(fire: endDate, interval: 0, repeats: false) { [weak self] _ in self?.finish() }
        RunLoop.main.add(timer, forMode: .common)
        finishTimer = timer
    }

    private func finish() {
        cancel()
        NSSound(named: soundName)?.play()
        onFinish?()
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(endDate?.timeIntervalSince1970, forKey: Key.end)
        defaults.set(pausedRemaining, forKey: Key.paused)
        defaults.set(duration, forKey: Key.duration)
    }

    /// A timer that ran out while the app was closed is cleared quietly.
    private func restore() {
        let defaults = UserDefaults.standard
        duration = defaults.double(forKey: Key.duration)
        if let paused = defaults.object(forKey: Key.paused) as? Double {
            pausedRemaining = paused
        } else if let end = defaults.object(forKey: Key.end) as? Double,
                  Date(timeIntervalSince1970: end) > Date() {
            endDate = Date(timeIntervalSince1970: end)
            scheduleFinish()
        } else {
            cancel()
        }
    }
}

extension TimeInterval {
    /// "4:59" or "1:04:59".
    var clockText: String {
        let total = Int(rounded(.up))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
