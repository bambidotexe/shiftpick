import XCTest
import ShiftPickCore

/// When the app looks for a release without being asked.
final class UpdateScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testTheFirstCheckIsAlwaysDue() {
        XCTAssertTrue(UpdateSchedule().isDue(now: now))
    }

    func testAWeekAfterTheLastAnswer() {
        var schedule = UpdateSchedule()
        schedule.answered(at: now)
        XCTAssertFalse(schedule.isDue(now: now.addingTimeInterval(K.updateInterval - 1)))
        XCTAssertTrue(schedule.isDue(now: now.addingTimeInterval(K.updateInterval)))
    }

    func testAFailedCheckWaitsAnHourAndThenTriesAgain() {
        var schedule = UpdateSchedule()
        schedule.failed(at: now)
        XCTAssertFalse(schedule.isDue(now: now.addingTimeInterval(K.updateRetryDelay - 1)))
        XCTAssertTrue(schedule.isDue(now: now.addingTimeInterval(K.updateRetryDelay)))
    }

    func testAnAnswerClearsTheFailure() {
        var schedule = UpdateSchedule()
        schedule.failed(at: now)
        schedule.answered(at: now)
        XCTAssertFalse(schedule.isDue(now: now.addingTimeInterval(60)))
    }

    /// A clock set back leaves a date in the future, which holds nothing.
    func testADateInTheFutureIsNotBelieved() {
        var schedule = UpdateSchedule()
        schedule.answered(at: now.addingTimeInterval(10_000))
        XCTAssertTrue(schedule.isDue(now: now))
    }
}
