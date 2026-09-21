import XCTest
@testable import ShiftPickCore

/// The Health page's rules: which colour each state takes, what the overview sums up, which files are this
/// app's crash reports, and what the copied report says. The same colour rule colours the System page's
/// permission row, so what is pinned here holds on both pages.
final class HealthTests: XCTestCase {
    override func tearDown() {
        Loc.language = .en
        super.tearDown()
    }

    private func facts(granted: Bool = true, systemSays: Bool? = nil, listener: TapLifecycle.Status = .watching,
                       userEnabled: Bool = true, finderRunning: Bool? = true,
                       loginItem: LoginItemState = .enabled, crashes: [Date] = [],
                       location: AppLocation = .applications) -> HealthFacts {
        HealthFacts(accessibilityGranted: granted, accessibilitySystemSays: systemSays ?? granted,
                    accessibilityRequired: true, listener: listener, userEnabled: userEnabled,
                    macOSVersion: "27.0", macOSBuild: "Version 27.0 (Build 27A1)", finderRunning: finderRunning,
                    loginItem: loginItem, runningSeconds: 3_720, memoryBytes: 48 * 1_048_576,
                    recentCrashes: crashes, location: location, bundlePath: "/Applications/ShiftPick.app")
    }

    private func row(_ id: String, in groups: [HealthGroup]) -> HealthRow? {
        groups.flatMap(\.rows).first { $0.id == id }
    }

    private func group(_ id: String, in groups: [HealthGroup]) -> HealthGroup? {
        groups.first { $0.id == id }
    }

    // MARK: Levels

    func testAMissingGrantIsRedOnlyWhenTheWizardMarksItRequired() {
        XCTAssertEqual(HealthRules.grant(held: true, required: true), .good)
        XCTAssertEqual(HealthRules.grant(held: true, required: false), .good)
        XCTAssertEqual(HealthRules.grant(held: false, required: true), .failure)
        XCTAssertEqual(HealthRules.grant(held: false, required: false), .warning)
    }

    func testALoginItemSwitchedOffHereIsOnlyWorthKnowing() {
        XCTAssertEqual(HealthRules.loginItem(.enabled), .good)
        XCTAssertEqual(HealthRules.loginItem(.disabled), .info)
        XCTAssertEqual(HealthRules.loginItem(.needsApproval), .warning)
    }

    func testAnyCrashIsWorthALook() {
        XCTAssertEqual(HealthRules.crashes(0), .good)
        XCTAssertEqual(HealthRules.crashes(1), .warning)
    }

    func testAnAppThatIsNotInstalledIsWorthALook() {
        XCTAssertEqual(HealthRules.location(.applications), .good)
        XCTAssertEqual(HealthRules.location(.elsewhere(folder: "Tools")), .info)
        XCTAssertEqual(HealthRules.location(.diskImage), .warning)
        XCTAssertEqual(HealthRules.location(.temporaryCopy), .warning)
    }

    /// The listener is what the whole app rests on: not listening while switched on is red, unless it only
    /// waits for the permission, whose own row is the red one. Switched off by the user is the state they
    /// asked for.
    func testAListenerThatIsNotListeningWhileSwitchedOnIsRed() {
        XCTAssertEqual(HealthRules.listener(.watching, userEnabled: true), .good)
        XCTAssertEqual(HealthRules.listener(.needsPermission, userEnabled: true), .info)
        XCTAssertEqual(HealthRules.listener(.refused, userEnabled: true), .failure)
        XCTAssertEqual(HealthRules.listener(.breakerOpen, userEnabled: true), .failure)
        XCTAssertNil(HealthRules.listener(.stopped, userEnabled: true), "nothing reported yet is no row")
    }

    func testShiftPickSwitchedOffByTheUserIsBlue() {
        for status in [TapLifecycle.Status.watching, .needsPermission, .refused, .breakerOpen] {
            XCTAssertEqual(HealthRules.listener(status, userEnabled: false), .info, "\(status)")
        }
    }

    func testFinderNotRunningDegradesWithoutStopping() {
        XCTAssertEqual(HealthRules.finder(running: true), .good)
        XCTAssertEqual(HealthRules.finder(running: false), .warning)
    }

    func testRedWinsOverOrangeInTheOverview() {
        let rows = [HealthRow(id: "a", label: "A", level: .warning, word: "x"),
                    HealthRow(id: "b", label: "B", level: .failure, word: "x"),
                    HealthRow(id: "c", label: "C", level: .info, word: "x")]
        let summary = HealthSummary(groups: [HealthGroup(id: "g", title: "G", rows: rows)])
        XCTAssertEqual(summary.blocking, 1)
        XCTAssertEqual(summary.toLookAt, 1)
        XCTAssertEqual(summary.level, .failure)
        XCTAssertEqual(HealthReport.summaryWord(summary), "Not working: 1 problem")
    }

    func testBlueRowsCountForNothing() {
        let rows = [HealthRow(id: "a", label: "A", level: .info, word: "x"),
                    HealthRow(id: "b", label: "B", level: .good, word: "x")]
        let summary = HealthSummary(groups: [HealthGroup(id: "g", title: "G", rows: rows)])
        XCTAssertEqual(summary.level, .good)
        XCTAssertEqual(HealthReport.summaryWord(summary), "Everything works")
    }

    // MARK: Warnings

    func testAFixIsShownOnlyWhileItsRowIsOrangeOrRed() {
        let fine = HealthRow(id: "a", label: "A", level: .good, word: "x", fix: "Do this.")
        let wrong = HealthRow(id: "b", label: "B", level: .warning, word: "x", fix: "Do that.")
        let twice = HealthRow(id: "c", label: "C", level: .failure, word: "x", fix: "Do that.")
        XCTAssertEqual(HealthGroup(id: "g", title: "G", rows: [fine, wrong, twice]).warnings, ["Do that."])
        XCTAssertEqual(HealthGroup(id: "g", title: "G", rows: [fine]).warnings, [])
    }

    // MARK: The page, group by group

    func testTheGroupsComeInPageOrder() {
        XCTAssertEqual(HealthReport.groups(for: facts()).map(\.id), ["permissions", "clicks", "compatibility", "app"])
    }

    func testAHealthyShiftPickReadsGreenAndBlue() {
        let groups = HealthReport.groups(for: facts())
        XCTAssertEqual(HealthSummary(groups: groups).level, .good)
        XCTAssertEqual(row("accessibility", in: groups)?.word, "Granted")
        XCTAssertEqual(row("listener", in: groups)?.word, "Enabled")
        XCTAssertEqual(row("macos", in: groups)?.level, .info)
        XCTAssertEqual(row("finder", in: groups)?.word, "Running")
        XCTAssertEqual(row("running for", in: groups)?.word, "1 h 2 min")
        XCTAssertEqual(row("memory", in: groups)?.word, "48 MB")
        XCTAssertEqual(row("crashes", in: groups)?.word, "None")
        XCTAssertEqual(row("location", in: groups)?.word, "Applications")
        XCTAssertTrue(groups.allSatisfy(\.warnings.isEmpty), "a healthy app shows no warning")
    }

    /// The grant missing stops everything: the permission is red with its switch named, and the listener,
    /// which starts on its own once it is granted, waits in blue, so one cause is one problem.
    func testTheGrantMissingIsOneRedRowAndSaysWhereToGrantIt() {
        let groups = HealthReport.groups(for: facts(granted: false, listener: .needsPermission))
        let grant = row("accessibility", in: groups)
        XCTAssertEqual(grant?.level, .failure)
        XCTAssertEqual(grant?.word, "Denied")
        XCTAssertEqual(group("permissions", in: groups)?.warnings, [Loc.settings.system.accessibilityWarning])
        XCTAssertEqual(row("listener", in: groups)?.level, .info)
        XCTAssertEqual(row("listener", in: groups)?.word, "Waiting")
        XCTAssertEqual(group("clicks", in: groups)?.warnings, [])
        XCTAssertEqual(HealthReport.summaryWord(HealthSummary(groups: groups)), "Not working: 1 problem")
    }

    /// The row shows what it is given, which the page takes through `showsGrant`. When that disagrees with
    /// macOS's cached answer, the tooltip says so: it is the first thing a bug report about it needs.
    func testAGrantShiftPickFoundGoneWhileMacOSStillSaysYesSaysSoInItsDetail() {
        let groups = HealthReport.groups(for: facts(granted: false, systemSays: true, listener: .needsPermission))
        XCTAssertEqual(row("accessibility", in: groups)?.word, "Denied")
        XCTAssertEqual(row("accessibility", in: groups)?.detail, Loc.settings.health.grantFoundGoneDetail)
        XCTAssertNil(row("accessibility", in: HealthReport.groups(for: facts(granted: false)))?.detail)
    }

    func testEachWayTheListenerCanBeDownSaysHowToPutItRight() {
        let refused = HealthReport.groups(for: facts(listener: .refused))
        XCTAssertEqual(row("listener", in: refused)?.word, "Failed")
        XCTAssertEqual(group("clicks", in: refused)?.warnings, [Loc.settings.health.listenerRefusedFix])

        let breaker = HealthReport.groups(for: facts(listener: .breakerOpen))
        XCTAssertEqual(row("listener", in: breaker)?.word, "Stopped")
        XCTAssertEqual(row("listener", in: breaker)?.detail, "breakerOpen")
        XCTAssertEqual(group("clicks", in: breaker)?.warnings, [Loc.settings.health.listenerStoppedFix])
        XCTAssertEqual(HealthSummary(groups: breaker).blocking, 1)
    }

    func testShiftPickSwitchedOffIsBlueWithNothingToFix() {
        let groups = HealthReport.groups(for: facts(userEnabled: false))
        XCTAssertEqual(row("listener", in: groups)?.level, .info)
        XCTAssertEqual(row("listener", in: groups)?.word, "Disabled")
        XCTAssertEqual(group("clicks", in: groups)?.warnings, [])
        XCTAssertEqual(HealthSummary(groups: groups).level, .good)
    }

    func testNothingReportedYetIsNoRow() {
        let groups = HealthReport.groups(for: facts(listener: .stopped, finderRunning: nil))
        XCTAssertNil(group("clicks", in: groups))
        XCTAssertNil(row("finder", in: groups))
        XCTAssertNotNil(row("macos", in: groups))
    }

    func testFinderNotRunningSaysHowToBringItBack() {
        let groups = HealthReport.groups(for: facts(finderRunning: false))
        XCTAssertEqual(row("finder", in: groups)?.word, "Stopped")
        XCTAssertEqual(group("compatibility", in: groups)?.warnings, [Loc.settings.health.finderStoppedFix])
        XCTAssertEqual(HealthReport.summaryWord(HealthSummary(groups: groups)), "1 thing to look at")
    }

    func testACrashIsCountedAndDated() {
        let crash = Date(timeIntervalSince1970: 1_790_000_000)
        let groups = HealthReport.groups(for: facts(crashes: [crash]))
        let crashes = row("crashes", in: groups)
        XCTAssertEqual(crashes?.level, .warning)
        XCTAssertEqual(crashes?.word, "1")
        XCTAssertEqual(crashes?.detail, "Last one \(HealthReport.stamp(crash))")
        XCTAssertEqual(HealthSummary(groups: groups).toLookAt, 1)
    }

    func testALoginSwitchedOffInSystemSettingsSaysWhereToTurnItBackOn() {
        let groups = HealthReport.groups(for: facts(loginItem: .needsApproval))
        XCTAssertEqual(row("login item", in: groups)?.level, .warning)
        XCTAssertEqual(group("app", in: groups)?.warnings, [Loc.settings.health.loginItemNeedsApprovalFix])
    }

    /// Open at Login is a preference the wizard offers, not a grant: off is the user's choice.
    func testALoginItemTurnedOffIsBlue() {
        let groups = HealthReport.groups(for: facts(loginItem: .disabled))
        XCTAssertEqual(row("login item", in: groups)?.level, .info)
        XCTAssertEqual(row("login item", in: groups)?.word, "Disabled")
        XCTAssertEqual(HealthSummary(groups: groups).level, .good)
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

    // MARK: Location

    func testWhereTheBundleIs() {
        XCTAssertEqual(HealthRules.location(bundlePath: "/Applications/ShiftPick.app", home: "/Users/a",
                                            readOnlyVolume: false), .applications)
        XCTAssertEqual(HealthRules.location(bundlePath: "/Users/a/Applications/ShiftPick.app", home: "/Users/a",
                                            readOnlyVolume: false), .applications)
        XCTAssertEqual(HealthRules.location(bundlePath: "/Volumes/ShiftPick/ShiftPick.app", home: "/Users/a",
                                            readOnlyVolume: true), .diskImage)
        XCTAssertEqual(HealthRules.location(bundlePath: "/private/var/folders/x/AppTranslocation/1/d/ShiftPick.app",
                                            home: "/Users/a", readOnlyVolume: true), .temporaryCopy)
        XCTAssertEqual(HealthRules.location(bundlePath: "/Users/a/Tools/ShiftPick.app", home: "/Users/a",
                                            readOnlyVolume: false), .elsewhere(folder: "Tools"))
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

    // MARK: The report

    func testTheReportCarriesEveryRowWithItsLevel() {
        let groups = HealthReport.groups(for: facts(location: .diskImage))
        let text = HealthReport.text(appName: "ShiftPick", version: "1.0.0", system: "macOS 27.0.0", groups: groups)
        XCTAssertTrue(text.hasPrefix("ShiftPick 1.0.0, macOS 27.0.0\n1 thing to look at\n"))
        XCTAssertTrue(text.contains("[OK]   Accessibility permission: Granted"))
        XCTAssertTrue(text.contains("[OK]   Watching for clicks: Enabled (watching)"))
        XCTAssertTrue(text.contains("[INFO] macOS: 27.0 (Version 27.0 (Build 27A1))"))
        XCTAssertTrue(text.contains("[OK]   Launch at login: Enabled"))
        XCTAssertTrue(text.contains("[INFO] Memory used: 48 MB"))
        XCTAssertTrue(text.contains("[WARN] Installed in: Disk image (/Applications/ShiftPick.app)"))
    }
}
