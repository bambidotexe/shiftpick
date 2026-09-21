import XCTest
import ShiftPickCore
@testable import ShiftPickPlatform

/// The settings file: what is on disk is loaded as it is, and every change is written at once.
@MainActor
final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "shiftpick.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testAnEmptyDomainGivesTheDefaults() {
        XCTAssertEqual(SettingsStore(defaults: defaults).settings, Settings())
    }

    func testAChangeIsWrittenAtOnceAndReadBack() {
        let store = SettingsStore(defaults: defaults)
        store.settings.enabled = false
        store.settings.commandShiftAdds = false
        XCTAssertEqual(SettingsStore(defaults: defaults).settings.enabled, false)
        XCTAssertEqual(SettingsStore(defaults: defaults).settings.commandShiftAdds, false)
    }

    /// A blob written by an older build keeps what it says and defaults the rest, rather than throwing the
    /// whole file away.
    func testAnOlderBlobIsReadAsFarAsItGoes() {
        defaults.set(Data(#"{"enabled": false}"#.utf8), forKey: SettingsStore.defaultsKey)
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.settings.enabled)
        XCTAssertTrue(store.settings.showInMenuBar)
    }

    func testSomethingThatIsNotSettingsAtAllFallsBackToTheDefaults() {
        defaults.set(Data("not json".utf8), forKey: SettingsStore.defaultsKey)
        XCTAssertEqual(SettingsStore(defaults: defaults).settings, Settings())
    }
}
