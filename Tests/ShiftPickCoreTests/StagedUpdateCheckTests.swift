import XCTest
import ShiftPickCore

/// What the copy taken out of a disk image has to say about itself.
final class StagedUpdateCheckTests: XCTestCase {
    private let system = ReleaseVersion(27, 0, 0)

    private func facts(id: String? = "dev.rubens.ShiftPick", version: String? = "1.2.0",
                       minimum: String? = "26.0") -> StagedUpdateCheck.Facts {
        .init(bundleIdentifier: id, version: version, minimumSystemVersion: minimum)
    }

    func testANewerCopyOfThisAppIsAccepted() {
        XCTAssertNil(StagedUpdateCheck.rejection(staged: facts(),
                                                 runningIdentifier: "dev.rubens.ShiftPick",
                                                 runningVersion: "1.1.0", systemVersion: system))
    }

    func testAnotherAppIsRefused() {
        XCTAssertEqual(StagedUpdateCheck.rejection(staged: facts(id: "com.example.other"),
                                                   runningIdentifier: "dev.rubens.ShiftPick",
                                                   runningVersion: "1.1.0", systemVersion: system),
                       .wrongApp)
    }

    func testTheSameOrAnOlderVersionIsRefused() {
        XCTAssertEqual(StagedUpdateCheck.rejection(staged: facts(version: "1.1.0"),
                                                   runningIdentifier: "dev.rubens.ShiftPick",
                                                   runningVersion: "1.1.0", systemVersion: system),
                       .notNewer("1.1.0"))
    }

    func testACopyThatNeedsANewerMacOSIsRefused() {
        XCTAssertEqual(StagedUpdateCheck.rejection(staged: facts(minimum: "28.0"),
                                                   runningIdentifier: "dev.rubens.ShiftPick",
                                                   runningVersion: "1.1.0", systemVersion: system),
                       .needsNewerSystem("28.0"))
    }

    func testABinaryWithNoVersionOfItsOwnIsNeverReplaced() {
        XCTAssertEqual(StagedUpdateCheck.rejection(staged: facts(),
                                                   runningIdentifier: "dev.rubens.ShiftPick",
                                                   runningVersion: "", systemVersion: system),
                       .notNewer("1.2.0"))
    }
}
