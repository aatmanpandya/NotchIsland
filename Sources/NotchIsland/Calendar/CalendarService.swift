import AppKit
import EventKit
import SwiftUI

struct Meeting: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let color: Color
    /// A video-call link found in the event (Meet, Zoom, Teams, ...).
    let joinURL: URL?
}

/// Upcoming events from the user's calendars, and a heads-up shortly before each one.
final class CalendarService: ObservableObject {
    enum Access {
        case notDetermined
        case granted
        case denied
    }

    @Published private(set) var access: Access
    /// In-progress and upcoming events over the next week, soonest first.
    @Published private(set) var meetings: [Meeting] = []

    /// Called once per event, shortly before it starts (how early is a setting).
    var onMeetingSoon: ((Meeting) -> Void)?

    private static let lookahead: TimeInterval = 7 * 24 * 3600
    private static let meetingHosts = [
        "meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "webex.com",
        "whereby.com", "around.co", "chime.aws", "meet.jit.si", "gotomeeting.com",
    ]
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private let store = EKEventStore()
    private var announced: Set<String> = []
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    /// Preview mode shows made-up events, so real calendar changes must not replace them.
    private var showingSamples = false

    init() {
        access = Self.currentAccess()
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in self?.reload() }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.tick() }
        reload()
    }

    var next: Meeting? { meetings.first }
    var later: Meeting? { meetings.dropFirst().first }

    /// Asks only when the user taps the button in the panel, never at launch.
    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.access = Self.currentAccess()
                self?.reload()
            }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func useSampleMeetings() {
        showingSamples = true
        access = .granted
        let now = Date()
        meetings = [
            Meeting(id: "sample-1", title: "Design review", start: now.addingTimeInterval(4 * 60 + 30),
                    end: now.addingTimeInterval(34 * 60), color: .orange,
                    joinURL: URL(string: "https://meet.google.com/abc-defg-hij")),
            Meeting(id: "sample-2", title: "1:1 with Priya", start: now.addingTimeInterval(3 * 3600),
                    end: now.addingTimeInterval(3.5 * 3600), color: .purple, joinURL: nil),
        ]
        announced = Set(meetings.map(\.id))
    }

    // MARK: - Loading

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    private func reload() {
        guard !showingSamples else { return }
        guard access == .granted else {
            meetings = []
            return
        }
        let now = Date()
        // Start in the past so meetings already under way are included.
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-12 * 3600),
                                                 end: now.addingTimeInterval(Self.lookahead), calendars: nil)
        meetings = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled && !Self.isDeclined($0) }
            .sorted { $0.startDate < $1.startDate }
            .prefix(10)
            .map(Self.meeting(from:))
        tick()
    }

    /// Announces meetings about to start and drops ones that have ended.
    private func tick() {
        let now = Date()
        for meeting in meetings where !announced.contains(meeting.id) {
            let lead = meeting.start.timeIntervalSince(now)
            // A meeting that started under a minute ago still gets its heads-up.
            if lead <= Preferences.meetingLead, lead > -60 {
                announced.insert(meeting.id)
                onMeetingSoon?(meeting)
            }
        }
        if !showingSamples, meetings.contains(where: { $0.end <= now }) { reload() }
    }

    private static func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
    }

    private static func meeting(from event: EKEvent) -> Meeting {
        Meeting(
            // Repeating events share an identifier, so include the start time.
            id: "\(event.calendarItemIdentifier)-\(event.startDate.timeIntervalSince1970)",
            title: event.title?.isEmpty == false ? event.title : "Untitled event",
            start: event.startDate,
            end: event.endDate,
            color: event.calendar.map { Color(cgColor: $0.cgColor) } ?? .blue,
            joinURL: joinURL(for: event)
        )
    }

    /// The first video-call link in the event's URL, location or notes.
    private static func joinURL(for event: EKEvent) -> URL? {
        joinURL(in: [event.url?.absoluteString, event.location, event.notes].compactMap { $0 })
    }

    /// The first link to a known video-call service in these texts.
    static func joinURL(in texts: [String]) -> URL? {
        for text in texts {
            let matches = linkDetector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
            for match in matches {
                guard let url = match.url, let host = url.host?.lowercased() else { continue }
                if meetingHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
            }
        }
        return nil
    }
}

enum MeetingTime {
    /// "Up next · in 12 min", "Now · 18 min left", "Tomorrow", ...
    static func status(for meeting: Meeting, at now: Date) -> String {
        if meeting.start <= now {
            return "Now · \(spoken(minutes(until: meeting.end, from: now))) left"
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(meeting.start) {
            return "Up next · in \(spoken(minutes(until: meeting.start, from: now)))"
        }
        if calendar.isDateInTomorrow(meeting.start) { return "Tomorrow" }
        return meeting.start.formatted(.dateTime.weekday(.wide))
    }

    /// Short countdown for the pop-up: "4 min" or "now".
    static func countdown(to meeting: Meeting, at now: Date) -> String {
        meeting.start <= now ? "now" : "\(minutes(until: meeting.start, from: now)) min"
    }

    static func range(_ meeting: Meeting) -> String {
        let start = meeting.start.formatted(date: .omitted, time: .shortened)
        let end = meeting.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    /// "5 min", "1 hr 5 min": reads well in the panel's capitals, unlike "1h 05m".
    private static func spoken(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(rest) min"
    }

    private static func minutes(until date: Date, from now: Date) -> Int {
        max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
    }
}
