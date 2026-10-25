import SwiftUI

/// The right side of the expanded island: the next event, with a Join button for video calls.
struct UpNextPanel: View {
    @ObservedObject var calendar: CalendarService

    var body: some View {
        switch calendar.access {
        case .notDetermined:
            prompt(symbol: "calendar", title: "See your next meeting", action: "Allow Calendar Access") {
                calendar.requestAccess()
            }
        case .denied:
            prompt(symbol: "calendar.badge.exclamationmark", title: "Calendar access is off", action: "Open Settings") {
                calendar.openPrivacySettings()
            }
        case .granted:
            if let next = calendar.next {
                MeetingSummary(meeting: next, later: calendar.later)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Nothing coming up")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Your week is clear.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    private func prompt(symbol: String, title: String, action: String, perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.5))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Button(action: perform) {
                Text(action)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .islandGlass(in: Capsule(), interactive: true)
            }
            .buttonStyle(PressScaleStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct MeetingSummary: View {
    let meeting: Meeting
    let later: Meeting?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle().fill(meeting.color).frame(width: 7, height: 7)
                    Text(MeetingTime.status(for: meeting, at: context.date))
                        .font(.system(size: 10, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(meeting.color)
                        .lineLimit(1)
                }
                Text(meeting.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                Text(MeetingTime.range(meeting))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 4)
                if let url = meeting.joinURL {
                    JoinButton(url: url, color: meeting.color)
                }
                if let later {
                    Text("Later · \(later.title)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

struct JoinButton: View {
    let url: URL
    let color: Color

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Label("Join", systemImage: "video.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(color.opacity(0.9)))
                .shadow(color: color.opacity(0.5), radius: 6)
        }
        .buttonStyle(PressScaleStyle())
        .help(url.host ?? "Join")
    }
}
