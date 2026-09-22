import XCTest
import ShiftPickCore
@testable import ShiftPickPlatform

/// The settings file: what is on disk is loaded as it is, and every change is written at once.
@MainActor
final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    /// One domain, always the same, emptied before and after every test. A domain of its own per test left its
    /// emptied file behind in `~/Library/Preferences` at every run, because `cfprefsd` keeps an emptied
    /// domain's plist; with one name there is at most one such file, and the next run reuses it.
    private static let suite = "shiftpick.tests.settingsstore"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: Self.suite)
        defaults.removePersistentDomain(forName: Self.suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.suite)
        super.tearDown()
    }

    func testAnEmptyDomainGivesTheDefaults() {
        XCTAssertEqual(SettingsStore(defaults: defaults).settings, Settings())
    }

    func testAChangeIsWrittenAtOnceAndReadBack() {
        let store = SettingsStore(defaults: defaults)
        store.settings.showInMenuBar = false
        store.settings.onboardingCompleted = true
        XCTAssertEqual(SettingsStore(defaults: defaults).settings.showInMenuBar, false)
        XCTAssertEqual(SettingsStore(defaults: defaults).settings.onboardingCompleted, true)
    }

    /// A blob written by an older build keeps what it says and defaults the rest, rather than throwing the
    /// whole file away.
    func testAnOlderBlobIsReadAsFarAsItGoes() {
        defaults.set(Data(#"{"enabled": false, "onboardingCompleted": true}"#.utf8), forKey: SettingsStore.defaultsKey)
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.settings.onboardingCompleted)
        XCTAssertTrue(store.settings.showInMenuBar)
    }

    func testSomethingThatIsNotSettingsAtAllFallsBackToTheDefaults() {
        defaults.set(Data("not json".utf8), forKey: SettingsStore.defaultsKey)
        XCTAssertEqual(SettingsStore(defaults: defaults).settings, Settings())
    }
}
