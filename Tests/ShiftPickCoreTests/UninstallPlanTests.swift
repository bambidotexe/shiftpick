import XCTest
import ShiftPickCore

/// What the uninstall's detached helper is told to remove, and how it quotes what it is given.
final class UninstallPlanTests: XCTestCase {
    private func script(home: String = "/Users/someone") -> String {
        UninstallPlan.helperScript(pid: 4_242, supportDirectory: "\(home)/Library/Application Support/ShiftPick",
                                   bundleIdentifier: "dev.rubens.ShiftPick", home: home) ?? ""
    }

    private func script(identifier: String = "dev.rubens.ShiftPick", home: String = "/Users/someone",
                        support: String? = nil) -> String? {
        UninstallPlan.helperScript(pid: 4_242,
                                   supportDirectory: support ?? "\(home)/Library/Application Support/ShiftPick",
                                   bundleIdentifier: identifier, home: home)
    }

    // MARK: - What the helper may be pointed at

    /// The helper runs `rm -rf`. Every path it is given is built from the app's name and its bundle
    /// identifier, and an identifier that came back empty would make one of them `~/Library/Caches/`.
    func testAnIdentifierThatIsNotOneProducesNoScript() {
        for identifier in ["", " ", ".", "..", "nodot", "dev..ShiftPick", ".dev.ShiftPick", "dev.ShiftPick.",
                           "dev/rubens.ShiftPick", "../../x.y", "dev.rubens.Shift Pick", "dev.rubens;rm -rf ~",
                           "dev.rubens.$(id)", "dev.rubens.'x'", "dev.rubens.é"] {
            XCTAssertNil(script(identifier: identifier), "\"\(identifier)\" was taken for a bundle identifier")
        }
    }

    func testAnOrdinaryIdentifierIsOne() {
        for identifier in ["dev.rubens.ShiftPick", "io.my-sidepulse.app", "a.b", "com.example.App2"] {
            XCTAssertNotNil(script(identifier: identifier), identifier)
        }
    }

    /// One folder of its own, directly inside Application Support, and nothing else.
    func testASupportFolderThatIsNotTheAppsOwnProducesNoScript() {
        let home = "/Users/someone"
        for support in ["\(home)/Library/Application Support", "\(home)/Library/Application Support/",
                        "\(home)/Library/Application Support/.", "\(home)/Library/Application Support/..",
                        "\(home)/Library/Application Support/ShiftPick/../..",
                        "\(home)/Library/Application Support/a/b", "\(home)/Library", home, "/", "",
                        "Library/Application Support/ShiftPick", "/Users/other/Library/Application Support/ShiftPick",
                        "\(home)/Library/Application Support/ShiftPick/"] {
            XCTAssertNil(script(home: home, support: support), "\"\(support)\" was taken for the app's own folder")
        }
    }

    func testAHomeThatIsNotAFolderOfItsOwnProducesNoScript() {
        for home in ["", "/", "Users/someone", "/Users/someone/", "/Users/../someone", "/Users//someone", "/Users/./someone"] {
            XCTAssertNil(script(home: home, support: "\(home)/Library/Application Support/ShiftPick"),
                         "\"\(home)\" was taken for a home folder")
        }
    }

    func testAnAppWithASpaceInItsNameStillHasAFolderOfItsOwn() {
        XCTAssertNotNil(script(support: "/Users/someone/Library/Application Support/Shift Pick"))
    }

    func testAHomeWithASpaceInItIsStillAHome() {
        XCTAssertNotNil(script(home: "/Users/some one"))
        XCTAssertNotNil(script(home: "/Volumes/External Disk/Users/someone"))
    }

    /// Quoted as well as checked: the one line of the helper that named it bare.
    func testTheIdentifierIsNeverHandedToTheShellBare() throws {
        let text = try XCTUnwrap(script(identifier: "dev.rubens.ShiftPick"))
        XCTAssertTrue(text.contains("/usr/bin/defaults delete 'dev.rubens.ShiftPick'"), text)
    }

    // MARK: - What it does

    func testItWaitsForTheAppToGoBeforeItTouchesAnything() {
        let text = script()
        let wait = try? XCTUnwrap(text.split(separator: "\n").first { $0.hasPrefix("while") })
        XCTAssertNotNil(wait)
        XCTAssertTrue(text.contains("/bin/kill -0 4242"))
        // The wait is bounded: a helper that could spin for ever is worse than one that stops.
        XCTAssertTrue(text.contains("-lt \(UninstallPlan.helperWaitTenths)"))
    }

    func testThePreferencesAreDroppedBeforeTheFileIsRemoved() {
        let text = script()
        guard let defaults = text.range(of: "/usr/bin/defaults delete"),
              let remove = text.range(of: "/bin/rm -rf") else { return XCTFail("both steps are missing") }
        // cfprefsd writes its cache back over the gap otherwise.
        XCTAssertTrue(defaults.lowerBound < remove.lowerBound)
    }

    func testEverythingNamedAfterTheBundleIdentifierGoes() {
        let text = script()
        for path in ["Library/Application Support/ShiftPick",
                     "Library/Preferences/dev.rubens.ShiftPick.plist",
                     "Library/Caches/dev.rubens.ShiftPick",
                     "Library/HTTPStorages/dev.rubens.ShiftPick",
                     "Library/Saved Application State/dev.rubens.ShiftPick.savedState"] {
            XCTAssertTrue(text.contains(path), path)
        }
        XCTAssertTrue(text.contains("Preferences/ByHost"))
    }

    func testAHomeFolderWithAQuoteInItIsStillQuotedSafely() {
        let text = script(home: "/Users/it's mine")
        XCTAssertTrue(text.contains("'/Users/it'\\''s mine/Library/Preferences/dev.rubens.ShiftPick.plist'"),
                      text)
    }

    func testTheQuotingCloseAndReopensAroundEveryQuote() {
        XCTAssertEqual(UninstallPlan.shellQuoted("/a/b"), "'/a/b'")
        XCTAssertEqual(UninstallPlan.shellQuoted("/a'b"), "'/a'\\''b'")
    }

    func testWhatIsLeftToCheckAfterwards() {
        let remains = UninstallPlan.remains(bundlePath: "/Applications/ShiftPick.app",
                                            bundleIdentifier: "dev.rubens.ShiftPick",
                                            supportDirectory: "/Users/x/Library/Application Support/ShiftPick")
        XCTAssertEqual(remains.count, 3)
    }
}
