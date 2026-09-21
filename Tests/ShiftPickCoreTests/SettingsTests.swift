import XCTest
import ShiftPickCore

/// The three switches, and the rule that keeps an older settings file from resetting the other two.
final class SettingsTests: XCTestCase {
    func testTheDefaultsAreOnAndOnAndOn() {
        let settings = Settings()
        XCTAssertTrue(settings.enabled)
        XCTAssertTrue(settings.commandShiftAdds)
        XCTAssertTrue(settings.showInMenuBar)
    }

    func testAFileWrittenByAnOlderBuildKeepsWhatItSaysAndDefaultsTheRest() throws {
        let data = Data(#"{"enabled": false}"#.utf8)
        let settings = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertFalse(settings.enabled)
        XCTAssertTrue(settings.commandShiftAdds)
        XCTAssertTrue(settings.showInMenuBar)
    }

    func testAnEmptyFileIsEveryDefault() throws {
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)), Settings())
    }

    func testItSurvivesARoundTrip() throws {
        var settings = Settings()
        settings.enabled = false
        settings.commandShiftAdds = false
        settings.showInMenuBar = false
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: data), settings)
    }
}
