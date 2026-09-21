import XCTest
import ShiftPickCore

/// The update window's state machine, from Update to the quit.
final class UpdateSessionTests: XCTestCase {
    private func session(size: Int64? = 1_000) -> UpdateSession {
        UpdateSession(release: LatestRelease(version: ReleaseVersion(1, 2, 0),
                                             dmgURL: URL(string: "https://example.invalid/a.dmg")!,
                                             dmgSize: size))
    }

    func testItStartsByDownloading() {
        let session = session()
        XCTAssertEqual(session.phase, .downloading(received: 0, expected: 1_000))
        XCTAssertEqual(session.fraction, 0)
        XCTAssertFalse(session.canInstall)
        XCTAssertTrue(session.canCancel)
    }

    func testTheBarFollowsTheBytes() {
        var session = session()
        session.received(250, of: 1_000)
        XCTAssertEqual(session.fraction ?? 0, 0.25, accuracy: 0.001)
    }

    func testAResponseWithNoLengthKeepsGitHubsFigure() {
        var session = session(size: 2_000)
        session.received(500, of: 0)
        XCTAssertEqual(session.fraction ?? 0, 0.25, accuracy: 0.001)
    }

    func testWithNoTotalAtAllTheBarIsIndeterminate() {
        var session = session(size: nil)
        session.received(500, of: 0)
        XCTAssertNil(session.fraction)
    }

    func testInstallIsEnabledOnlyOnceEverythingHasBeenChecked() {
        var session = session()
        session.downloaded()
        XCTAssertEqual(session.phase, .preparing)
        XCTAssertFalse(session.canInstall)
        session.prepared()
        XCTAssertEqual(session.phase, .ready)
        XCTAssertTrue(session.canInstall)
    }

    func testTheInstallStartsOnceAndOnlyOnce() {
        var session = session()
        session.downloaded()
        session.prepared()
        XCTAssertTrue(session.install())
        XCTAssertFalse(session.install())
        XCTAssertFalse(session.canCancel)
    }

    func testAnAppThatDidNotQuitGoesBackToReadyAndSaysSo() {
        var session = session()
        session.downloaded()
        session.prepared()
        _ = session.install()
        session.installStalled()
        XCTAssertEqual(session.phase, .ready)
        XCTAssertTrue(session.stalled)
        XCTAssertTrue(session.canInstall)
    }

    func testAnAppThatCannotReplaceItselfOffersTheDiskImage() {
        var session = session()
        session.downloaded()
        session.cannotReplace()
        XCTAssertEqual(session.phase, .manual)
        XCTAssertEqual(session.fraction, 1)
        XCTAssertFalse(session.canInstall)
    }

    func testAFailureCanBeRetriedFromTheStart() {
        var session = session()
        session.failed("offline")
        XCTAssertEqual(session.phase, .failed("offline"))
        XCTAssertTrue(session.retry())
        XCTAssertEqual(session.phase, .downloading(received: 0, expected: 1_000))
        XCTAssertFalse(session.retry())
    }

    func testAnInstallUnderWayCannotBeFailed() {
        var session = session()
        session.downloaded()
        session.prepared()
        _ = session.install()
        session.failed("anything")
        XCTAssertEqual(session.phase, .installing)
    }
}
