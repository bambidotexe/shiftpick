import XCTest
import ShiftPickCore

/// The one switch, the flag the onboarding wizard writes, and the rule that keeps an older settings file
/// from resetting the rest. ShiftPick has no setting about what it does: the feature is always on, one way.
final class SettingsTests: XCTestCase {
    func testTheDefaultIsOn() {
        XCTAssertTrue(Settings().showInMenuBar)
    }

    /// A fresh install has not walked the wizard, so the wizard opens.
    func testOnboardingStartsUnwalked() {
        XCTAssertFalse(Settings().onboardingCompleted)
    }

    /// A file written by a build that still had *Enable ShiftPick* and the ⌘ Command switch loads, the two
    /// keys ignored, and keeps what it says about the rest.
    func testAFileWrittenByAnOlderBuildKeepsWhatItSaysAndIgnoresTheRest() throws {
        let data = Data(#"{"enabled": false, "commandShiftAdds": false, "showInMenuBar": false}"#.utf8)
        let settings = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertFalse(settings.showInMenuBar)
        XCTAssertFalse(settings.onboardingCompleted)
    }

    func testAFileFromBeforeTheWizardOpensTheWizard() throws {
        let data = Data(#"{"showInMenuBar": true}"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(Settings.self, from: data).onboardingCompleted)
    }

    func testAnEmptyFileIsEveryDefault() throws {
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)), Settings())
    }

    func testItSurvivesARoundTrip() throws {
        var settings = Settings()
        settings.showInMenuBar = false
        settings.onboardingCompleted = true
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: data), settings)
    }
}
