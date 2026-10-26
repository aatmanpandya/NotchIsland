import SwiftUI
import XCTest
@testable import NotchIsland

final class JoinLinkTests: XCTestCase {
    func testFindsKnownCallServices() {
        XCTAssertEqual(CalendarService.joinURL(in: ["Join at https://meet.google.com/abc-defg-hij"])?.host,
                       "meet.google.com")
        XCTAssertEqual(CalendarService.joinURL(in: ["https://acme.zoom.us/j/123456789"])?.host, "acme.zoom.us")
        XCTAssertNotNil(CalendarService.joinURL(in: ["https://teams.microsoft.com/l/meetup-join/xyz"]))
    }

    func testIgnoresOtherLinks() {
        XCTAssertNil(CalendarService.joinURL(in: ["Agenda: https://docs.google.com/document/d/1"]))
        XCTAssertNil(CalendarService.joinURL(in: ["https://notzoom.us.example.com/j/1"]))
        XCTAssertNil(CalendarService.joinURL(in: []))
    }

    func testTakesTheFirstCallLinkAcrossFields() {
        let url = CalendarService.joinURL(in: ["Room 4", "Docs https://example.com then https://meet.google.com/aaa"])
        XCTAssertEqual(url?.host, "meet.google.com")
    }
}

final class MeetingTimeTests: XCTestCase {
    private func meeting(startingIn minutes: Double, lasting length: Double = 30, from now: Date) -> Meeting {
        Meeting(id: "m", title: "Standup", start: now.addingTimeInterval(minutes * 60),
                end: now.addingTimeInterval((minutes + length) * 60), color: .blue, joinURL: nil)
    }

    /// Noon today, so "today" checks don't cross midnight.
    private var noon: Date { Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())! }

    func testUpcomingTodayCountsDown() {
        XCTAssertEqual(MeetingTime.status(for: meeting(startingIn: 12, from: noon), at: noon), "Up next · in 12 min")
        XCTAssertEqual(MeetingTime.status(for: meeting(startingIn: 90, from: noon), at: noon), "Up next · in 1 hr 30 min")
        XCTAssertEqual(MeetingTime.status(for: meeting(startingIn: 120, from: noon), at: noon), "Up next · in 2 hr")
    }

    func testInProgressShowsTimeLeft() {
        XCTAssertEqual(MeetingTime.status(for: meeting(startingIn: -10, lasting: 30, from: noon), at: noon),
                       "Now · 20 min left")
    }

    func testTomorrow() {
        let tomorrow = meeting(startingIn: 24 * 60, from: noon)
        XCTAssertEqual(MeetingTime.status(for: tomorrow, at: noon), "Tomorrow")
    }

    func testCountdownForThePopUp() {
        XCTAssertEqual(MeetingTime.countdown(to: meeting(startingIn: 4.2, from: noon), at: noon), "5 min")
        XCTAssertEqual(MeetingTime.countdown(to: meeting(startingIn: -1, from: noon), at: noon), "now")
    }
}
