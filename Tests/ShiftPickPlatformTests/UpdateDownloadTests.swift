import CryptoKit
import XCTest
import ShiftPickCore
@testable import ShiftPickPlatform

/// What a finished download is held against before anything opens it.
final class UpdateDownloadTests: XCTestCase {
    private var file: URL!

    override func setUpWithError() throws {
        file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shiftpick-download-\(UUID().uuidString).dmg")
        try Data("a disk image, more or less".utf8).write(to: file)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: file)
    }

    private func release(size: Int64?, sha: String?) -> LatestRelease {
        LatestRelease(version: ReleaseVersion(1, 2, 0),
                      dmgURL: URL(string: "https://example.invalid/a.dmg")!,
                      dmgSize: size, dmgSHA256: sha)
    }

    private var digest: String {
        let data = try! Data(contentsOf: file)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private var length: Int64 {
        Int64((try! FileManager.default.attributesOfItem(atPath: file.path)[.size] as! NSNumber).intValue)
    }

    func testWhatGitHubStatedHasToHold() throws {
        XCTAssertTrue(try UpdateDownload.matches(release(size: length, sha: digest), file: file))
    }

    func testAFileOfTheWrongLengthIsRefused() throws {
        XCTAssertFalse(try UpdateDownload.matches(release(size: length + 1, sha: nil), file: file))
    }

    func testAFileWithTheWrongDigestIsRefused() throws {
        XCTAssertFalse(try UpdateDownload.matches(release(size: nil, sha: String(repeating: "0", count: 64)),
                                                  file: file))
    }

    /// What GitHub did not state is not held against the file.
    func testAReleaseThatStatesNothingAcceptsWhatArrived() throws {
        XCTAssertTrue(try UpdateDownload.matches(release(size: nil, sha: nil), file: file))
    }
}
