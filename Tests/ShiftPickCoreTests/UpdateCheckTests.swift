import XCTest
import ShiftPickCore

/// The update check's decision, which is the whole of it that can be tested without a network: what a
/// version string means, what a GitHub reply means, and when a release counts as newer than the running
/// app. Making the request is `ShiftPickPlatform.UpdateChecker`'s and is not exercised here.
final class UpdateCheckTests: XCTestCase {
    private func release(_ version: String) -> LatestRelease {
        LatestRelease(version: ReleaseVersion(string: version)!,
                      dmgURL: URL(string: "https://example.invalid/ShiftPick-\(version).dmg")!)
    }

    private func json(tag: String? = "v1.2.0", assets: [String] = ["ShiftPick-1.2.0.dmg"],
                      digest: String? = nil, size: Int64? = nil) -> Data {
        let list = assets.map { name -> String in
            var fields = ["\"name\": \"\(name)\"",
                          "\"browser_download_url\": \"https://example.invalid/\(name)\""]
            if let size { fields.append("\"size\": \(size)") }
            if let digest { fields.append("\"digest\": \"\(digest)\"") }
            return "{ " + fields.joined(separator: ", ") + " }"
        }.joined(separator: ",")
        let tagField = tag.map { "\"tag_name\": \"\($0)\"," } ?? ""
        return Data("{ \(tagField) \"assets\": [\(list)] }".utf8)
    }

    // MARK: A version

    func testAVersionParsesWithOrWithoutItsTagsV() {
        XCTAssertEqual(ReleaseVersion(string: "1.2.0"), ReleaseVersion(1, 2, 0))
        XCTAssertEqual(ReleaseVersion(string: "v1.2.0"), ReleaseVersion(1, 2, 0))
        XCTAssertEqual(ReleaseVersion(string: "v1.2")?.displayString, "1.2")
    }

    func testWhatIsNotAVersionIsRefused() {
        for bad in ["", "v", "nightly", "1.2.beta", "1..2", "-1.0.0"] {
            XCTAssertNil(ReleaseVersion(string: bad), bad)
        }
    }

    func testVersionsCompareByNumberAndNotAsText() {
        XCTAssertTrue(ReleaseVersion(string: "1.0.9")! < ReleaseVersion(string: "1.0.10")!)
        XCTAssertEqual(ReleaseVersion(string: "1.7"), ReleaseVersion(string: "1.7.0"))
        XCTAssertTrue(ReleaseVersion(string: "2.0")! > ReleaseVersion(string: "1.99.99")!)
    }

    // MARK: A release

    func testAReleaseNeedsATagAndADiskImage() {
        XCTAssertNotNil(LatestRelease.parse(json()))
        XCTAssertNil(LatestRelease.parse(json(tag: nil)))
        XCTAssertNil(LatestRelease.parse(json(tag: "nightly")))
        XCTAssertNil(LatestRelease.parse(json(assets: ["ShiftPick.zip"])))
        XCTAssertNil(LatestRelease.parse(Data("not json".utf8)))
    }

    func testTheAssetsLengthAndDigestAreReadWhenGitHubStatesThem() {
        let hex = String(repeating: "ab", count: 32)
        let parsed = LatestRelease.parse(json(digest: "sha256:\(hex)", size: 4_096))
        XCTAssertEqual(parsed?.dmgSize, 4_096)
        XCTAssertEqual(parsed?.dmgSHA256, hex)
    }

    func testADigestThatIsNotASHA256IsIgnoredRatherThanBelieved() {
        XCTAssertNil(LatestRelease.parse(json(digest: "md5:abc"))?.dmgSHA256)
        XCTAssertNil(LatestRelease.parse(json(digest: "sha256:nothex"))?.dmgSHA256)
        XCTAssertNil(LatestRelease.parse(json(size: 0))?.dmgSize)
    }

    // MARK: The decision

    func testOnlyAStrictlyNewerReleaseIsOffered() {
        XCTAssertEqual(UpdateCheck.decide(current: "1.0.0", latest: release("1.0.1")),
                       .available(release("1.0.1")))
        XCTAssertEqual(UpdateCheck.decide(current: "1.0.1", latest: release("1.0.1")), .upToDate)
        XCTAssertEqual(UpdateCheck.decide(current: "1.0.2", latest: release("1.0.1")), .upToDate)
    }

    func testABinaryWithNoVersionIsNeverOfferedAnything() {
        XCTAssertEqual(UpdateCheck.decide(current: "", latest: release("9.9.9")), .upToDate)
    }

    func testA404MeansNothingPublishedAndNotAFailure() {
        XCTAssertEqual(try? UpdateCheck.interpret(status: 404, body: Data(), current: "1.0.0").get(),
                       .noRelease)
    }

    func testAnErrorStatusIsAFailure() {
        guard case .failure(let failure) = UpdateCheck.interpret(status: 503, body: Data(), current: "1.0.0")
        else { return XCTFail("503 should fail") }
        XCTAssertEqual(failure, .httpStatus(503))
    }

    func testAReplyThatCannotBeReadIsAFailure() {
        guard case .failure(let failure) = UpdateCheck.interpret(status: 200, body: Data("{}".utf8),
                                                                 current: "1.0.0")
        else { return XCTFail("a reply with no release should fail") }
        XCTAssertEqual(failure, .malformedResponse)
    }

    func testTheAPIURLNamesTheRepositoryTheBundleStates() {
        XCTAssertTrue(UpdateCheck.latestReleaseAPI.absoluteString
            .hasPrefix("https://api.github.com/repos/\(AppIdentity.repository)/releases/latest"))
    }
}
