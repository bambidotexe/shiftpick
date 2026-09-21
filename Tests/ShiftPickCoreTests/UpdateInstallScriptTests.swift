import XCTest
import ShiftPickCore

/// The install helper, run for real by `/bin/sh`.
///
/// It is the one piece of this app that runs when the app is already gone, so it has no compiler behind it
/// and no way to say what went wrong: the only honest test is to give it two folders and see which one ends
/// up where. `open` and `ps` are stubbed through the environment, which is the one seam the script has.
final class UpdateInstallScriptTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shiftpick-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Building a stand-in world

    /// A folder shaped like an app bundle, with a readable executable inside it.
    private func bundle(_ name: String, marker: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        let binary = url.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: binary, withIntermediateDirectories: true)
        let executable = binary.appendingPathComponent("ShiftPick")
        try marker.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return url
    }

    /// A `ps` that answers "this executable is running" or does not, and never says the app is alive.
    private func stubPS(reporting running: String?) throws -> URL {
        let url = root.appendingPathComponent("ps")
        let body = """
        #!/bin/sh
        case "$1" in
          -o) exit 1 ;;
        esac
        \(running.map { "printf '%s\\n' '\($0)'" } ?? "true")
        """
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// An `open` that records that it was asked.
    private func stubOpen() throws -> (tool: URL, record: URL) {
        let record = root.appendingPathComponent("opened")
        let url = root.appendingPathComponent("open")
        try "#!/bin/sh\nprintf '%s\\n' \"$1\" >> '\(record.path)'\n"
            .write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return (url, record)
    }

    /// Runs the helper to completion. The pid is one that cannot be alive, so it starts at once.
    @discardableResult
    private func run(_ plan: UpdateInstallPlan, ps: URL, open: URL) throws -> Int32 {
        let script = root.appendingPathComponent("install.sh")
        try UpdateInstallScript.text.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path] + plan.arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                               "UPDATE_HELPER_PS": ps.path,
                               "UPDATE_HELPER_OPEN": open.path]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func plan(destination: URL, staged: URL) -> UpdateInstallPlan {
        UpdateInstallPlan(pid: 999_999,
                          destination: destination, staged: staged,
                          backup: root.appendingPathComponent("previous/ShiftPick.app"),
                          resultFile: root.appendingPathComponent("result"),
                          logFile: root.appendingPathComponent("install.log"),
                          executableName: "ShiftPick", version: "1.2.0",
                          quitWait: 1, launchWait: 1, settle: 0)
    }

    private func marker(at bundle: URL) -> String? {
        try? String(contentsOf: bundle.appendingPathComponent("Contents/MacOS/ShiftPick"), encoding: .utf8)
    }

    private func result() -> UpdateResult? {
        guard let line = try? String(contentsOf: root.appendingPathComponent("result"), encoding: .utf8)
        else { return nil }
        return UpdateResult(line: line)
    }

    // MARK: The three outcomes

    func testTheNewVersionTakesTheOldOnesPlace() throws {
        let destination = try bundle("ShiftPick.app", marker: "old")
        let staged = try bundle("staged/ShiftPick.app", marker: "new")
        let open = try stubOpen()
        let ps = try stubPS(reporting: destination.appendingPathComponent("Contents/MacOS/ShiftPick").path)

        try run(plan(destination: destination, staged: staged), ps: ps, open: open.tool)

        XCTAssertEqual(marker(at: destination), "new")
        XCTAssertEqual(result(), .installed(version: "1.2.0"))
        // The previous copy is only kept until the new version has been seen running.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("previous/ShiftPick.app").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: open.record.path))
    }

    func testAVersionThatDoesNotStartIsRolledBack() throws {
        let destination = try bundle("ShiftPick.app", marker: "old")
        let staged = try bundle("staged/ShiftPick.app", marker: "new")
        let open = try stubOpen()
        // A `ps` that never sees the new version running.
        let ps = try stubPS(reporting: nil)

        try run(plan(destination: destination, staged: staged), ps: ps, open: open.tool)

        XCTAssertEqual(marker(at: destination), "old")
        XCTAssertEqual(result(), .failed(version: "1.2.0", reason: .launch))
    }

    func testAMissingStagedCopyTouchesNothing() throws {
        let destination = try bundle("ShiftPick.app", marker: "old")
        let staged = root.appendingPathComponent("staged/ShiftPick.app")
        let open = try stubOpen()
        let ps = try stubPS(reporting: nil)

        try run(plan(destination: destination, staged: staged), ps: ps, open: open.tool)

        XCTAssertEqual(marker(at: destination), "old")
        XCTAssertEqual(result(), .failed(version: "1.2.0", reason: .replace))
    }

    /// The helper is the one thing that runs when nothing else can report: it says what it did.
    func testItWritesALog() throws {
        let destination = try bundle("ShiftPick.app", marker: "old")
        let staged = try bundle("staged/ShiftPick.app", marker: "new")
        let open = try stubOpen()
        let ps = try stubPS(reporting: destination.appendingPathComponent("Contents/MacOS/ShiftPick").path)
        try run(plan(destination: destination, staged: staged), ps: ps, open: open.tool)
        let log = try String(contentsOf: root.appendingPathComponent("install.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("installing 1.2.0"), log)
        XCTAssertTrue(log.contains("version 1.2.0 is running"), log)
    }

    // MARK: The line it leaves behind

    func testTheResultLineIsReadBackAsItWasWritten() {
        for outcome: UpdateResult in [.installed(version: "1.2.0"),
                                      .failed(version: "1.2.0", reason: .replace),
                                      .failed(version: "1.2.0", reason: .launch),
                                      .failed(version: "1.2.0", reason: .stranded)] {
            XCTAssertEqual(UpdateResult(line: outcome.line), outcome)
        }
        XCTAssertNil(UpdateResult(line: "something else"))
        XCTAssertNil(UpdateResult(line: "failed 1.2.0 nonsense"))
    }

    func testAResultNobodyIsWaitingOnIsNotNews() {
        XCTAssertTrue(UpdateResult.isNews(age: 1))
        XCTAssertFalse(UpdateResult.isNews(age: K.updateResultShelfLife + 1))
        XCTAssertFalse(UpdateResult.isNews(age: -5))
    }

    func testThePlansArgumentsAreInTheOrderTheScriptReadsThem() {
        let plan = plan(destination: root.appendingPathComponent("a.app"),
                        staged: root.appendingPathComponent("b.app"))
        XCTAssertEqual(plan.arguments.count, 11)
        XCTAssertEqual(plan.arguments[0], "999999")
        XCTAssertEqual(plan.arguments[6], "ShiftPick")
        XCTAssertEqual(plan.arguments[7], "1.2.0")
    }
}
