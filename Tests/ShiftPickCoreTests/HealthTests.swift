import XCTest
@testable import ShiftPickCore

/// The Health page's rules: which colour each check takes, which lines appear only while they are wrong, how
/// long the two tables may grow, and which files are this app's crash reports. The same colour rule colours
/// the System page's permission row, so what is pinned here holds on both pages.
final class HealthTests: XCTestCase {
    override func tearDown() {
        Loc.language = .en
        super.tearDown()
    }

    private func facts(granted: Bool = true, systemSays: Bool? = nil, listener: TapLifecycle.Status = .watching,
                       finderRunning: Bool? = true, crashes: [Date] = []) -> HealthFacts {
        HealthFacts(accessibilityGranted: granted, accessibilitySystemSays: systemSays ?? granted,
                    accessibilityRequired: true, listener: listener,
                    finderRunning: finderRunning, runningSeconds: 3_720, memoryBytes: 48 * 1_048_576,
                    recentCrashes: crashes)
    }

    private func check(_ id: String, in facts: HealthFacts) -> HealthRow? {
        HealthReport.checks(for: facts).first { $0.id == id }
    }

    // MARK: Levels

    func testAMissingGrantIsRedOnlyWhenTheWizardMarksItRequired() {
        XCTAssertEqual(HealthRules.grant(held: true, required: true), .good)
        XCTAssertEqual(HealthRules.grant(held: true, required: false), .good)
        XCTAssertEqual(HealthRules.grant(held: false, required: true), .failure)
        XCTAssertEqual(HealthRules.grant(held: false, required: false), .warning)
    }

    /// The listener is what the whole app rests on: not listening is red.
    func testAListenerThatIsNotListeningIsRed() {
        XCTAssertEqual(HealthRules.listener(.watching), .good)
        XCTAssertEqual(HealthRules.listener(.refused), .failure)
        XCTAssertEqual(HealthRules.listener(.breakerOpen), .failure)
    }

    /// No line while waiting for the permission (the permission's own line says it: one cause, one line), and
    /// none before anything was reported.
    func testTheListenerHasNoLineInItsTwoQuietCases() {
        XCTAssertNil(HealthRules.listener(.needsPermission))
        XCTAssertNil(HealthRules.listener(.stopped))
        XCTAssertNil(check("listener", in: facts(listener: .stopped)), "nothing reported yet is no row")
    }

    func testAFixIsShownOnlyWhileItsRowIsOrangeOrRed() {
        let fine = HealthRow(id: "a", label: "A", level: .good, word: "x", fix: "Do this.")
        let wrong = HealthRow(id: "b", label: "B", level: .warning, word: "x", fix: "Do that.")
        let twice = HealthRow(id: "c", label: "C", level: .failure, word: "x", fix: "Do that.")
        XCTAssertEqual([fine, wrong, twice].warnings, ["Do that."])
        XCTAssertEqual([fine].warnings, [])
    }

    // MARK: The Health table

    func testAHealthyShiftPickIsTwoGreenLines() {
        let checks = HealthReport.checks(for: facts())
        XCTAssertEqual(checks.map(\.id), ["accessibility", "listener"])
        XCTAssertTrue(checks.allSatisfy { $0.level == .good })
        XCTAssertEqual(checks.map(\.word), ["Granted", "Enabled"])
        XCTAssertEqual(checks.warnings, [], "a healthy app shows no warning")
    }

    /// The grant missing stops everything: the permission is red with its switch named, and the listener,
    /// which starts on its own once it is granted, has no line, so one cause is one line.
    func testTheGrantMissingIsOneRedLineAndSaysWhereToGrantIt() {
        let checks = HealthReport.checks(for: facts(granted: false, listener: .needsPermission))
        XCTAssertEqual(checks.map(\.id), ["accessibility"])
        XCTAssertEqual(checks.first?.level, .failure)
        XCTAssertEqual(checks.first?.word, "Denied")
        XCTAssertEqual(checks.warnings, [Loc.settings.system.accessibilityWarning])
    }

    /// The line shows what it is given, which the page takes through `showsGrant`. When that disagrees with
    /// macOS's cached answer, the tooltip says so: it is the first thing a bug report about it needs.
    func testAGrantShiftPickFoundGoneWhileMacOSStillSaysYesSaysSoInItsTooltip() {
        let gone = facts(granted: false, systemSays: true, listener: .needsPermission)
        XCTAssertEqual(check("accessibility", in: gone)?.word, "Denied")
        XCTAssertEqual(check("accessibility", in: gone)?.detail, Loc.settings.health.grantFoundGoneDetail)
        XCTAssertNil(check("accessibility", in: facts(granted: false))?.detail)
    }

    func testEachWayTheListenerCanBeDownSaysHowToPutItRight() {
        let refused = facts(listener: .refused)
        XCTAssertEqual(check("listener", in: refused)?.word, "Failed")
        XCTAssertEqual(check("listener", in: refused)?.level, .failure)
        XCTAssertEqual(HealthReport.checks(for: refused).warnings, [Loc.settings.health.listenerRefusedFix])

        let breaker = facts(listener: .breakerOpen)
        XCTAssertEqual(check("listener", in: breaker)?.word, "Stopped")
        XCTAssertEqual(check("listener", in: breaker)?.detail, "breakerOpen")
        XCTAssertEqual(HealthReport.checks(for: breaker).warnings, [Loc.settings.health.listenerStoppedFix])
    }

    func testTheListenersWordIsSharedByBothPages() {
        XCTAssertEqual(HealthReport.listenerWord(.watching), Loc.settings.words.enabled)
        XCTAssertEqual(HealthReport.listenerWord(.breakerOpen), Loc.settings.health.stopped)
        XCTAssertEqual(HealthReport.listenerWord(.refused), Loc.settings.words.failed)
    }

    func testFinderIsALineOnlyWhileItIsNotRunning() {
        XCTAssertNil(check("finder", in: facts()))
        XCTAssertNil(check("finder", in: facts(finderRunning: nil)), "not read yet is no line")
        let stopped = facts(finderRunning: false)
        XCTAssertEqual(check("finder", in: stopped)?.level, .warning)
        XCTAssertEqual(check("finder", in: stopped)?.word, "Stopped")
        XCTAssertEqual(HealthReport.checks(for: stopped).warnings, [Loc.settings.health.finderStoppedFix])
    }

    func testACrashIsALineOnlyWhileThereIsOne() {
        XCTAssertNil(check("crashes", in: facts()))
        let crash = Date(timeIntervalSince1970: 1_790_000_000)
        let crashes = check("crashes", in: facts(crashes: [crash]))
        XCTAssertEqual(crashes?.level, .warning)
        XCTAssertEqual(crashes?.word, "1")
        XCTAssertEqual(crashes?.detail, "Last one \(HealthReport.stamp(crash))")
        XCTAssertEqual(crashes?.fix, Loc.settings.health.crashesFix)
    }

    func testTheTablesStayShortInTheWorstCase() {
        let worst = facts(listener: .breakerOpen, finderRunning: false, crashes: [Date(), Date()])
        XCTAssertEqual(HealthReport.checks(for: worst).count, 4)
        XCTAssertLessThanOrEqual(HealthReport.checks(for: worst).count, HealthLimits.checks)
        XCTAssertLessThanOrEqual(HealthReport.checks(for: facts(granted: false, listener: .refused,
                                                                 finderRunning: false, crashes: [Date()])).count,
                                 HealthLimits.checks)
        XCTAssertLessThanOrEqual(HealthReport.readings(for: worst).count, HealthLimits.readings)
    }

    // MARK: The Information table

    func testTheReadings() {
        let readings = HealthReport.readings(for: facts())
        XCTAssertEqual(readings.map(\.id), ["running for", "memory"])
        XCTAssertEqual(readings.map(\.value), ["1 h 2 min", "48 MB"])
    }

    // MARK: Crash reports

    func testOnlyThisProcesssCrashReportsAreCounted() {
        XCTAssertTrue(HealthRules.isCrashReport(fileName: "ShiftPick-2026-09-21-101010.ips", process: "ShiftPick"))
        XCTAssertTrue(HealthRules.isCrashReport(fileName: "ShiftPick-2026-09-21-101010.crash", process: "ShiftPick"))
        XCTAssertTrue(HealthRules.isCrashReport(fileName: "ShiftPick-2026-09-21-101010-1.ips", process: "ShiftPick"))
        XCTAssertFalse(HealthRules.isCrashReport(fileName: "ExcUserFault_ShiftPick-2026-09-21-101010.ips",
                                                  process: "ShiftPick"))
        XCTAssertFalse(HealthRules.isCrashReport(fileName: "ShiftPickHelper-2026-09-21-101010.ips",
                                                  process: "ShiftPick"))
        XCTAssertFalse(HealthRules.isCrashReport(fileName: "ShiftPick-notes.ips", process: "ShiftPick"))
        XCTAssertFalse(HealthRules.isCrashReport(fileName: "ShiftPick-2026-09-21-101010.diag", process: "ShiftPick"))
    }

    // MARK: The words

    func testDurationsReadInTheTwoLargestUnits() {
        let t = Loc.settings.health
        XCTAssertEqual(t.duration(seconds: 30), "Less than a minute")
        XCTAssertEqual(t.duration(seconds: 125), "2 min")
        XCTAssertEqual(t.duration(seconds: 3_720), "1 h 2 min")
        XCTAssertEqual(t.duration(seconds: 2 * 86_400 + 3 * 3_600 + 59), "2 d 3 h")
        Loc.language = .fr
        XCTAssertEqual(Loc.settings.health.duration(seconds: 2 * 86_400 + 3 * 3_600), "2 j 3 h")
    }
}
