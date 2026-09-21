import XCTest
@testable import ShiftPickPlatform

/// The one way this app ever starts another process: the uninstall's helper and the update's, both of which
/// have to outlive it.
final class DetachedProcessTests: XCTestCase {
    func testAChildRunsAndIsInAProcessGroupOfItsOwn() throws {
        let marker = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shiftpick-detached-\(UUID().uuidString)")
        let pid = try DetachedProcess.spawn(
            executable: "/bin/sh",
            arguments: ["-c", "printf '%s' \"$$\" > '\(marker.path)'"],
            environment: ["PATH": "/usr/bin:/bin"])
        XCTAssertGreaterThan(pid, 0)
        // It is not our child to wait for, so the file is what says it ran.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !FileManager.default.fileExists(atPath: marker.path) {
            usleep(20_000)
        }
        let text = try String(contentsOf: marker, encoding: .utf8)
        XCTAssertEqual(Int32(text), pid, "the child is its own process group leader")
        try? FileManager.default.removeItem(at: marker)
    }

    func testAnExecutableThatIsNotThereThrows() {
        XCTAssertThrowsError(try DetachedProcess.spawn(executable: "/nowhere/at/all",
                                                        arguments: [], environment: [:]))
    }
}
