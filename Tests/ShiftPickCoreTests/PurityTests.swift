import XCTest
import ShiftPickCore

/// `ShiftPickCore` decides everything that can be decided from values alone, so it imports Foundation and
/// CoreGraphics and nothing else. A frameworks import would make a rule untestable without the system it
/// came from, which is the whole reason the layer exists.
final class PurityTests: XCTestCase {
    private static let allowed: Set<String> = ["Foundation", "CoreGraphics"]

    func testCoreImportsNothingButFoundationAndCoreGraphics() throws {
        let core = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ShiftPickCore")
        let files = try FileManager.default.contentsOfDirectory(at: core, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "no sources were found at \(core.path)")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n") where line.hasPrefix("import ") {
                let module = String(line.dropFirst("import ".count))
                    .trimmingCharacters(in: .whitespaces)
                XCTAssertTrue(Self.allowed.contains(module),
                              "\(file.lastPathComponent) imports \(module)")
            }
        }
    }

    /// Core never reads a clock: every rule that depends on time is handed the time. `UpdateSchedule` and
    /// `QuietLaunch` take a `now`, and nothing calls `Date()` with no argument except the one place a
    /// default argument makes it convenient.
    func testCoreNeverReachesForTheClockInARule() throws {
        let core = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ShiftPickCore")
        let files = try FileManager.default.contentsOfDirectory(at: core, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "QuietLaunch.swift" }
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains("Date()"),
                           "\(file.lastPathComponent) reads the clock; pass the time in instead")
        }
    }
}
