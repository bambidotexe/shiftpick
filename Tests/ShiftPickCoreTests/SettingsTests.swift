import XCTest
import ShiftPickCore

/// The three switches, the flag the onboarding wizard writes, and the rule that keeps an older settings file
/// from resetting the rest.
final class SettingsTests: XCTestCase {
    func testTheDefaultsAreOnAndOnAndOn() {
        let settings = Settings()
        XCTAssertTrue(settings.enabled)
        XCTAssertTrue(settings.commandShiftAdds)
        XCTAssertTrue(settings.showInMenuBar)
    }

    /// A fresh install has not walked the wizard, so the wizard opens.
    func testOnboardingStartsUnwalked() {
        XCTAssertFalse(Settings().onboardingCompleted)
    }

    func testAFileWrittenByAnOlderBuildKeepsWhatItSaysAndDefaultsTheRest() throws {
        let data = Data(#"{"enabled": false}"#.utf8)
        let settings = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertFalse(settings.enabled)
        XCTAssertTrue(settings.commandShiftAdds)
        XCTAssertTrue(settings.showInMenuBar)
        XCTAssertFalse(settings.onboardingCompleted)
    }

    /// A file written before the wizard existed defaults the flag to false, so the wizard opens once for
    /// someone who has been using the app for months. Deliberate: it is the only place that says what the
    /// permission is for.
    func testAFileFromBeforeTheWizardOpensTheWizard() throws {
        let data = Data(#"{"enabled": true, "commandShiftAdds": true, "showInMenuBar": true}"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(Settings.self, from: data).onboardingCompleted)
    }

    func testAnEmptyFileIsEveryDefault() throws {
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)), Settings())
    }

    func testItSurvivesARoundTrip() throws {
        var settings = Settings()
        settings.enabled = false
        settings.commandShiftAdds = false
        settings.showInMenuBar = false
        settings.onboardingCompleted = true
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: data), settings)
    }
}
