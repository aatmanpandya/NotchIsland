import XCTest
@testable import NotchIsland

final class TimerServiceTests: XCTestCase {
    private var timer: TimerService!

    override func setUp() {
        timer = TimerService()
        timer.cancel()
    }

    override func tearDown() {
        timer.cancel()
    }

    func testStartRunsForTheChosenTime() {
        timer.start(seconds: 300)
        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(timer.remaining(at: Date()), 300, accuracy: 1)
        XCTAssertEqual(timer.progress(at: Date()), 0, accuracy: 0.01)
    }

    func testPauseFreezesTheTimeLeftAndResumeContinues() {
        timer.start(seconds: 300)
        timer.pause()
        XCTAssertFalse(timer.isRunning)
        XCTAssertTrue(timer.isActive)
        XCTAssertEqual(timer.remaining(at: Date().addingTimeInterval(100)), 300, accuracy: 1)
        timer.resume()
        XCTAssertTrue(timer.isRunning)
    }

    func testAddMinuteExtendsARunningTimer() {
        timer.start(seconds: 60)
        timer.addMinute()
        XCTAssertEqual(timer.remaining(at: Date()), 120, accuracy: 1)
    }

    func testAddMinuteWithNoTimerStartsOne() {
        timer.addMinute()
        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(timer.remaining(at: Date()), 60, accuracy: 1)
    }

    func testCancelClearsEverything() {
        timer.start(seconds: 60)
        timer.cancel()
        XCTAssertFalse(timer.isActive)
        XCTAssertEqual(timer.remaining(at: Date()), 0)
    }

    func testDisplayLabelFallsBackToTimer() {
        timer.label = "  "
        XCTAssertEqual(timer.displayLabel, "Timer")
        timer.label = "Tea"
        XCTAssertEqual(timer.displayLabel, "Tea")
        timer.label = ""
    }
}

final class StopwatchServiceTests: XCTestCase {
    func testStartsStoppedAndEmpty() {
        let stopwatch = StopwatchService()
        XCTAssertFalse(stopwatch.isRunning)
        XCTAssertFalse(stopwatch.hasTime)
        XCTAssertEqual(stopwatch.elapsed(at: Date()), 0)
    }

    func testStopKeepsTheTimeAndResetClearsIt() {
        let stopwatch = StopwatchService()
        stopwatch.start()
        Thread.sleep(forTimeInterval: 0.05)
        stopwatch.stop()
        let stopped = stopwatch.elapsed(at: Date())
        XCTAssertGreaterThan(stopped, 0)
        XCTAssertEqual(stopwatch.elapsed(at: Date().addingTimeInterval(10)), stopped, accuracy: 0.0001)
        stopwatch.reset()
        XCTAssertFalse(stopwatch.hasTime)
    }

    func testLapsAreNewestFirst() {
        let stopwatch = StopwatchService()
        stopwatch.start()
        stopwatch.lap()
        stopwatch.lap()
        XCTAssertEqual(stopwatch.laps.count, 2)
        stopwatch.stop()
        stopwatch.lap() // ignored while stopped
        XCTAssertEqual(stopwatch.laps.count, 2)
    }
}

final class FormattingTests: XCTestCase {
    func testClockText() {
        XCTAssertEqual(TimeInterval(65).clockText, "1:05")
        XCTAssertEqual(TimeInterval(3_725).clockText, "1:02:05")
        XCTAssertEqual(TimeInterval(59.2).clockText, "1:00") // counts down, so partial seconds round up
    }

    func testStopwatchText() {
        XCTAssertEqual(TimeInterval(12.345).stopwatchText, "00:12.34")
        XCTAssertEqual(TimeInterval(3_661.5).stopwatchText, "1:01:01.50")
    }

    func testDurationText() {
        XCTAssertEqual(42.durationText, "42m")
        XCTAssertEqual(65.durationText, "1h 05m")
    }
}
