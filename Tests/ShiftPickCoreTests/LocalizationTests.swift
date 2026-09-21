import XCTest
import ShiftPickCore

/// Every sentence the user reads, in both languages, held to the window's copy rules.
///
/// The tables are Swift, so "the French is missing" is a compile error rather than a test failure. What is
/// left for a test is the text itself: the rules the owner fitted by eye, which no compiler can see.
final class LocalizationTests: XCTestCase {
    /// Every dash that is longer than the one on the keyboard. None of them may appear in anything a user
    /// reads: two sentences, a comma or a colon instead.
    private static let longDashes: Set<Character> = ["\u{2014}", "\u{2013}", "\u{2012}", "\u{2015}",
                                                     "\u{2010}", "\u{2011}", "\u{2212}"]

    /// Every accessor of every table, for one language. Written out rather than reflected: a table added
    /// without a line here is a table nothing checks, and the compiler cannot say so.
    private func everySentence(_ language: Language) -> [(String, String)] {
        Loc.language = language
        var out: [(String, String)] = []
        func add(_ name: String, _ value: String) { out.append((name, value)) }

        let menu = Loc.menu
        for pair in [("menu.enable", menu.enable), ("menu.launchAtLogin", menu.launchAtLogin),
                     ("menu.settings", menu.settings), ("menu.quit", menu.quit),
                     ("menu.statusWatching", menu.statusWatching), ("menu.statusOff", menu.statusOff),
                     ("menu.statusNeedsPermission", menu.statusNeedsPermission),
                     ("menu.statusNoTap", menu.statusNoTap)] { add(pair.0, pair.1) }

        let main = Loc.mainMenu
        for pair in [("mainMenu.window", main.window), ("mainMenu.close", main.close),
                     ("mainMenu.minimize", main.minimize)] { add(pair.0, pair.1) }

        let onboarding = Loc.onboarding
        for pair in [("onboarding.windowTitle", onboarding.windowTitle),
                     ("onboarding.heading", onboarding.heading), ("onboarding.body", onboarding.body),
                     ("onboarding.steps", onboarding.steps),
                     ("onboarding.openSettingsButton", onboarding.openSettingsButton)] { add(pair.0, pair.1) }

        let settings = Loc.settings
        for pair in [("settings.pageGeneral", settings.pageGeneral),
                     ("settings.pageSelection", settings.pageSelection),
                     ("settings.pageTip", settings.pageTip),
                     ("settings.pageSystem", settings.pageSystem)] { add(pair.0, pair.1) }

        let words = settings.words
        for pair in [("words.granted", words.granted), ("words.denied", words.denied),
                     ("words.enabled", words.enabled), ("words.disabled", words.disabled),
                     ("words.failed", words.failed)] { add(pair.0, pair.1) }

        let general = settings.general
        for pair in [("general.startupTitle", general.startupTitle),
                     ("general.startupNote", general.startupNote),
                     ("general.launchAtLoginToggle", general.launchAtLoginToggle),
                     ("general.showInMenuBarToggle", general.showInMenuBarToggle),
                     ("general.loginItemFailed", general.loginItemFailed("x")),
                     ("general.updatesTitle", general.updatesTitle),
                     ("general.checking", general.checking), ("general.upToDate", general.upToDate),
                     ("general.versionAvailable", general.versionAvailable("1.2.0")),
                     ("general.noReleaseYet", general.noReleaseYet),
                     ("general.couldNotCheck", general.couldNotCheck("x")),
                     ("general.updateFailed", general.updateFailed("x")),
                     ("general.updateButton", general.updateButton),
                     ("general.checkForUpdatesButton", general.checkForUpdatesButton),
                     ("general.quitTitle", general.quitTitle), ("general.quitButton", general.quitButton),
                     ("general.uninstallTitle", general.uninstallTitle),
                     ("general.uninstallHint", general.uninstallHint),
                     ("general.uninstallWarning", general.uninstallWarning),
                     ("general.uninstallButton", general.uninstallButton),
                     ("general.uninstallConfirmTitle", general.uninstallConfirmTitle),
                     ("general.uninstallConfirmBody", general.uninstallConfirmBody),
                     ("general.uninstallConfirmButton", general.uninstallConfirmButton),
                     ("general.uninstallCancelButton", general.uninstallCancelButton),
                     ("general.uninstallDoneTitle", general.uninstallDoneTitle),
                     ("general.uninstallDoneBody", general.uninstallDoneBody),
                     ("general.uninstallPartialTitle", general.uninstallPartialTitle),
                     ("general.uninstallQuitButton", general.uninstallQuitButton),
                     ("general.uninstallGrantFailed", general.uninstallGrantFailed),
                     ("general.uninstallLoginItemFailed", general.uninstallLoginItemFailed("x")),
                     ("general.uninstallTrashFailed", general.uninstallTrashFailed("x")),
                     ("general.uninstallHelperFailed", general.uninstallHelperFailed("x"))] {
            add(pair.0, pair.1)
        }

        let selection = settings.selection
        for pair in [("selection.shiftClickTitle", selection.shiftClickTitle),
                     ("selection.shiftClickHint", selection.shiftClickHint),
                     ("selection.shiftClickNote", selection.shiftClickNote),
                     ("selection.enableToggle", selection.enableToggle),
                     ("selection.commandShiftToggle", selection.commandShiftToggle)] { add(pair.0, pair.1) }

        let tip = settings.tip
        for pair in [("tip.intro", tip.intro), ("tip.offerTitle", tip.offerTitle),
                     ("tip.offerName", tip.offerName),
                     ("tip.offerDescription", tip.offerDescription),
                     ("tip.offerHint", tip.offerHint(5)),
                     ("tip.tipButton", tip.tipButton(5))] { add(pair.0, pair.1) }

        let system = settings.system
        for pair in [("system.accessibilityTitle", system.accessibilityTitle),
                     ("system.accessibilityHint", system.accessibilityHint),
                     ("system.accessibilityNote", system.accessibilityNote),
                     ("system.accessibilityWarning", system.accessibilityWarning),
                     ("system.accessibilityRow", system.accessibilityRow),
                     ("system.openAccessibilityButton", system.openAccessibilityButton),
                     ("system.clicksTitle", system.clicksTitle),
                     ("system.clicksHint", system.clicksHint), ("system.clicksRow", system.clicksRow),
                     ("system.clicksWarningNoTap", system.clicksWarningNoTap),
                     ("system.clicksWarningDisabled", system.clicksWarningDisabled)] { add(pair.0, pair.1) }

        let update = Loc.update
        for pair in [("update.httpStatus", update.httpStatus(503)),
                     ("update.malformedResponse", update.malformedResponse),
                     ("update.damagedDownload", update.damagedDownload),
                     ("update.cannotOpenImage", update.cannotOpenImage),
                     ("update.appMissing", update.appMissing), ("update.notNewer", update.notNewer),
                     ("update.needsNewerSystem", update.needsNewerSystem("28.0")),
                     ("update.differentSigner", update.differentSigner),
                     ("update.invalidSignature", update.invalidSignature),
                     ("update.couldNotReplace", update.couldNotReplace),
                     ("update.didNotStart", update.didNotStart),
                     ("update.stranded", update.stranded)] { add(pair.0, pair.1) }

        let window = Loc.updateWindow
        for pair in [("updateWindow.windowTitle", window.windowTitle),
                     ("updateWindow.notificationBody", window.notificationBody),
                     ("updateWindow.downloading", window.downloading("1 MB", of: "2 MB")),
                     ("updateWindow.downloadingUnmeasured", window.downloadingUnmeasured),
                     ("updateWindow.preparing", window.preparing), ("updateWindow.ready", window.ready),
                     ("updateWindow.cannotReplaceItself", window.cannotReplaceItself),
                     ("updateWindow.installing", window.installing),
                     ("updateWindow.didNotQuit", window.didNotQuit),
                     ("updateWindow.installed", window.installed),
                     ("updateWindow.notInstalled", window.notInstalled("1.2.0", "x")),
                     ("updateWindow.doneButton", window.doneButton),
                     ("updateWindow.cancelButton", window.cancelButton),
                     ("updateWindow.closeButton", window.closeButton),
                     ("updateWindow.installButton", window.installButton),
                     ("updateWindow.openDiskImageButton", window.openDiskImageButton),
                     ("updateWindow.tryAgainButton", window.tryAgainButton),
                     ("updateWindow.updateAction", window.updateAction)] { add(pair.0, pair.1) }
        return out
    }

    override func tearDown() {
        Loc.language = .en
        super.tearDown()
    }

    func testEverySentenceExistsInBothLanguages() {
        for language in Language.allCases {
            for (name, sentence) in everySentence(language) {
                XCTAssertFalse(sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               "\(language.rawValue) \(name) is empty")
            }
        }
    }

    func testNoSentenceUsesADashLongerThanTheOneOnTheKeyboard() {
        for language in Language.allCases {
            for (name, sentence) in everySentence(language) where sentence.contains(where: Self.longDashes.contains) {
                XCTFail("\(language.rawValue) \(name) has a long dash: \(sentence)")
            }
        }
    }

    /// A key is its symbol, then its name, at every mention.
    func testEveryKeyIsWrittenWithItsSymbol() {
        let rules: [Language: [(String, String)]] = [
            .en: [("Shift", "⇧ Shift"), ("Command", "⌘ Command"), ("Option", "⌥ Option"),
                  ("Control", "⌃ Control")],
            .fr: [("Majuscule", "⇧ Majuscule"), ("Commande", "⌘ Commande"), ("Option", "⌥ Option")],
        ]
        for language in Language.allCases {
            for (name, sentence) in everySentence(language) {
                for (word, withSymbol) in rules[language] ?? [] {
                    guard sentence.contains(word) else { continue }
                    XCTAssertTrue(sentence.contains(withSymbol),
                                  "\(language.rawValue) \(name) says \(word) without its symbol: \(sentence)")
                }
            }
        }
    }

    /// The app's name is never translated, and every sentence that says it reads it from the bundle rather
    /// than spelling it out, so a rename carries through.
    func testTheAppsNameIsNeverSpeltOutInATable() throws {
        let core = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ShiftPickCore")
        let tables = try FileManager.default.contentsOfDirectory(at: core, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("Strings") }
        XCTAssertFalse(tables.isEmpty, "no string tables were found at \(core.path)")
        for table in tables {
            let text = try String(contentsOf: table, encoding: .utf8)
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }   // a comment is not a sentence
                guard code.contains("\""), code.contains("ShiftPick"),
                      !code.contains("AppIdentity.name") else { continue }
                XCTFail("\(table.lastPathComponent):\(number + 1) spells the app's name out: \(code)")
            }
        }
    }

    func testTheLanguageRuleReadsTheSystemsTag() {
        XCTAssertEqual(Language(preferredLanguage: "fr"), .fr)
        XCTAssertEqual(Language(preferredLanguage: "fr-CA"), .fr)
        XCTAssertEqual(Language(preferredLanguage: "fr_FR"), .fr)
        // Frisian is not French.
        XCTAssertEqual(Language(preferredLanguage: "fry"), .en)
        XCTAssertEqual(Language(preferredLanguage: "de-DE"), .en)
        XCTAssertEqual(Language(preferredLanguage: nil), .en)
    }
}
