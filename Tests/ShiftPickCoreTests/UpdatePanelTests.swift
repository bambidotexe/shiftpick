import XCTest
import ShiftPickCore

/// The Updates group: which button, what a press starts, and what an answer puts on the version row.
final class UpdatePanelTests: XCTestCase {
    private let newer = LatestRelease(version: ReleaseVersion(1, 2, 0),
                                      dmgURL: URL(string: "https://example.invalid/a.dmg")!)

    func testTheFirstPressAsksGitHub() {
        var panel = UpdatePanel()
        XCTAssertEqual(panel.state, .idle)
        XCTAssertEqual(panel.press(), .check)
        XCTAssertTrue(panel.isBusy)
    }

    func testASecondPressWhileCheckingStartsNothing() {
        var panel = UpdatePanel()
        _ = panel.press()
        XCTAssertNil(panel.press())
    }

    func testAKnownReleaseTurnsTheButtonIntoUpdate() {
        var panel = UpdatePanel()
        _ = panel.press()
        panel.checked(.available(newer))
        XCTAssertTrue(panel.offersUpdate)
        XCTAssertEqual(panel.state, .available(ReleaseVersion(1, 2, 0)))
        XCTAssertEqual(panel.press(), .update(newer))
        // Pressing again is the same request: it shows the window once more.
        XCTAssertEqual(panel.press(), .update(newer))
    }

    func testUpToDateClearsWhatWasPending() {
        var panel = UpdatePanel()
        _ = panel.press()
        panel.checked(.available(newer))
        _ = panel.press()
        panel.checked(.upToDate)
        XCTAssertFalse(panel.offersUpdate)
        XCTAssertEqual(panel.state, .upToDate)
    }

    func testACheckNobodyAskedForNeverInterruptsAPress() {
        var panel = UpdatePanel()
        _ = panel.press()
        panel.autoChecked(.available(newer))
        XCTAssertEqual(panel.state, .checking)
    }

    func testARepositoryWithNothingPublishedIsNoNewsWhenNobodyAsked() {
        var panel = UpdatePanel()
        panel.autoChecked(.noRelease)
        XCTAssertEqual(panel.state, .idle)
        _ = panel.press()
        panel.checked(.noRelease)
        XCTAssertEqual(panel.state, .noRelease)
    }

    func testAFailedInstallKeepsItsReasonAndStillOffersTheRetry() {
        var panel = UpdatePanel()
        panel.installFailed("the new version did not start")
        panel.autoChecked(.available(newer))
        XCTAssertEqual(panel.state, .installFailed("the new version did not start"))
        XCTAssertTrue(panel.offersUpdate)
    }

    func testAFailedCheckSaysSoAndOffersNothing() {
        var panel = UpdatePanel()
        _ = panel.press()
        panel.checkFailed("offline")
        XCTAssertEqual(panel.state, .checkFailed("offline"))
        XCTAssertFalse(panel.offersUpdate)
        XCTAssertEqual(panel.press(), .check)
    }
}
