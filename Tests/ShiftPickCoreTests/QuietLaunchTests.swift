import XCTest
import ShiftPickCore

/// The marker that tells a launch nobody asked for from one somebody did.
final class QuietLaunchTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testAMarkerJustWrittenIsFresh() {
        XCTAssertTrue(QuietLaunch.isFresh(writtenAt: now, now: now))
        XCTAssertTrue(QuietLaunch.isFresh(writtenAt: now, now: now.addingTimeInterval(QuietLaunch.window)))
    }

    func testAMarkerLeftBehindByAnInstallThatDiedLapses() {
        XCTAssertFalse(QuietLaunch.isFresh(writtenAt: now,
                                           now: now.addingTimeInterval(QuietLaunch.window + 1)))
    }

    /// A marker from the future is a clock that moved, not a fresh marker.
    func testAMarkerFromTheFutureIsNotBelieved() {
        XCTAssertFalse(QuietLaunch.isFresh(writtenAt: now.addingTimeInterval(60), now: now))
    }
}
