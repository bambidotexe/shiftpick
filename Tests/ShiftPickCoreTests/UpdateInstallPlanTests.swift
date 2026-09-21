import XCTest
import ShiftPickCore

/// What the install helper may be pointed at. It runs after the app has quit, with nobody left to stop it,
/// and its text renames the installed bundle aside and runs `rm -rf` on three of the paths it is handed.
final class UpdateInstallPlanTests: XCTestCase {
    private let updates = URL(fileURLWithPath: "/Users/someone/Library/Application Support/ShiftPick/updates")

    private func plan(destination: String = "/Applications/ShiftPick.app",
                      staged: String? = nil, backup: String? = nil, result: String? = nil, log: String? = nil,
                      executable: String = "ShiftPick", version: String = "1.2.0") -> UpdateInstallPlan {
        let root = updates.path
        return UpdateInstallPlan(
            pid: 4_242,
            destination: URL(fileURLWithPath: destination),
            staged: URL(fileURLWithPath: staged ?? "\(root)/staged/ShiftPick.app"),
            backup: URL(fileURLWithPath: backup ?? "\(root)/previous/ShiftPick.app"),
            resultFile: URL(fileURLWithPath: result ?? "\(root)/result"),
            logFile: URL(fileURLWithPath: log ?? "\(root)/install.log"),
            executableName: executable, version: version)
    }

    func testThePlanTheAppBuildsIsSafe() {
        XCTAssertTrue(plan().isSafe(updatesDirectory: updates))
    }

    func testOnlyAnAppBundleIsEverReplaced() {
        for destination in ["/Applications", "/", "/Applications/ShiftPick", "/Users/someone",
                            "/Applications/ShiftPick.app/Contents"] {
            XCTAssertFalse(plan(destination: destination).isSafe(updatesDirectory: updates), destination)
        }
    }

    /// `rm -rf "$backup"` is the helper's first act once the app has gone.
    func testWhatIsRemovedIsInsideTheUpdatesFolder() {
        for backup in ["/Applications/ShiftPick.app", "/Users/someone", "/", updates.path,
                       "\(updates.path)/../../ShiftPick.app", "\(updates.path)/previous/Other.app"] {
            XCTAssertFalse(plan(backup: backup).isSafe(updatesDirectory: updates), backup)
        }
    }

    func testTheNewCopyTheResultAndTheLogAreInsideTheUpdatesFolderToo() {
        XCTAssertFalse(plan(staged: "/tmp/ShiftPick.app").isSafe(updatesDirectory: updates))
        XCTAssertFalse(plan(staged: "\(updates.path)/staged/ShiftPick").isSafe(updatesDirectory: updates))
        XCTAssertFalse(plan(result: "/tmp/result").isSafe(updatesDirectory: updates))
        XCTAssertFalse(plan(log: "/tmp/install.log").isSafe(updatesDirectory: updates))
    }

    /// The helper looks for `<bundle>/Contents/MacOS/<name>` among the running processes, and writes the
    /// version into a line the next launch splits on spaces.
    func testTheNameAndTheVersionAreOneWordEach() {
        for executable in ["", "a/b", "..", "Shift Pick"] {
            XCTAssertFalse(plan(executable: executable).isSafe(updatesDirectory: updates), executable)
        }
        for version in ["", "1.2 .0", "1/2", "1.2.0\nfailed"] {
            XCTAssertFalse(plan(version: version).isSafe(updatesDirectory: updates), version)
        }
    }

    func testAnUpdatesFolderThatIsNotAPlainAbsolutePathIsNoAnchor() {
        XCTAssertFalse(plan().isSafe(updatesDirectory: URL(fileURLWithPath: "/")))
    }
}
