import XCTest
import ShiftPickCore
@testable import ShiftPickPlatform

/// Whether the app may replace itself where it is, decided before "Install and Relaunch" is enabled.
final class UpdateInstallerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shiftpick-obstacle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testABinaryThatIsNotInABundleCannotReplaceItself() {
        XCTAssertEqual(UpdateInstaller.obstacle(bundle: root.appendingPathComponent("build/ShiftPick"),
                                                updatesDirectory: root.appendingPathComponent("updates")),
                       .notInstalled)
    }

    func testACopyMacOSIsRunningFromSomewhereElseCannotReplaceItself() {
        let translocated = URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/ShiftPick.app")
        XCTAssertEqual(UpdateInstaller.obstacle(bundle: translocated,
                                                updatesDirectory: root.appendingPathComponent("updates")),
                       .translocated)
    }

    func testABundleInAWritableFolderOnTheSameVolumeCanBeReplaced() throws {
        let bundle = root.appendingPathComponent("ShiftPick.app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        XCTAssertNil(UpdateInstaller.obstacle(bundle: bundle,
                                              updatesDirectory: root.appendingPathComponent("updates")))
    }
}
