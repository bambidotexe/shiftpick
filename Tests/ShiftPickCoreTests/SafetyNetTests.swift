import XCTest
import ShiftPickCore

/// **The safety nets, pinned where they live.** ShiftPick holds an event tap that can swallow a click, and a
/// mistake around it once left a Mac taking no click and no key until the power button (`docs/pitfalls.md`
/// 13). When the click tap may be enabled is `Core/TapLifecycle`, which `TapLifecycleTests` and
/// `TapLifecycleInvariantTests` pin. These pin the rest, in code no test can run because a test runner has
/// no Accessibility grant to create a tap with: which tap may swallow, where it is enabled, which thread
/// serves it, what waits on what and for how long, and in which order the grant is taken away.
///
/// They read the source, the way `PurityTests` does, with comment lines left out. **If one fails because
/// code moved or was renamed, move the check with the code and keep what it asserts. If one fails because a
/// net is gone, put the net back.** Each is a guarantee in `docs/functional.md` §0; removing one is the
/// owner's decision, asked for in words, never an agent's. The `shiftpick-safety-nets` skill says what each
/// one is for.
final class SafetyNetTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let clickGuard = "Sources/ShiftPickPlatform/ClickGuard.swift"

    // MARK: - One tap can swallow, and one line enables it

    func testOnlyOneTapCanSwallowAClick() throws {
        let everything = try swiftFiles(under: ["Sources", "Tools"])
        XCTAssertEqual(occurrences(of: "tapCreate(", in: everything), [Self.clickGuard, Self.clickGuard], """
            Event taps are created in ClickGuard, two of them, and nowhere else, not even in Tools/axdump. \
            Another tap is another way to hold up every click on the Mac (docs/architecture.md, The safety model).
            """)
        XCTAssertEqual(occurrences(of: "options: .defaultTap", in: everything), [Self.clickGuard],
                       "One tap may swallow a click: ClickGuard's click tap.")
        XCTAssertEqual(occurrences(of: "options: .listenOnly", in: everything), [Self.clickGuard],
                       "The sentinel only listens, and a listener can hold nothing up whatever happens to the app.")
    }

    /// Two taps, and nothing else that touches the event stream. A global monitor is a tap by another name,
    /// a HID manager is one below the window server, and a posted event goes through every tap on the Mac,
    /// this app's included: each is a way to hold up or replay input that `TapLifecycle` knows nothing about.
    func testNothingElseTouchesTheEventStream() throws {
        let everything = try swiftFiles(under: ["Sources", "Tools"])
        for forbidden in [".post(tap:", "CGEventPost", "addGlobalMonitorForEvents", "IOHIDManager", "CGEventTapCreate"] {
            XCTAssertEqual(occurrences(of: forbidden, in: everything), [], """
                \(forbidden) reaches the event stream beside the two taps. Listening goes through the sentinel and \
                swallowing through the click tap, both under TapLifecycle; ShiftPick posts no event and holds no \
                monitor (docs/functional.md §1; CLAUDE.md, Where a change usually lands).
                """)
        }
    }

    func testTheClickTapIsEnabledInOnePlaceOnly() throws {
        XCTAssertEqual(occurrences(of: "tapEnable(tap: click, enable: true)", in: try swiftFiles(under: ["Sources"])),
                       [Self.clickGuard], """
            The click tap is enabled in exactly one place, ClickGuard.run under .enableClickTap, and only \
            TapLifecycle emits that effect. A second place is a defect whatever it is for (CLAUDE.md, Rules).
            """)
        let lines = try code(Self.clickGuard).components(separatedBy: "\n")
        let enable = try XCTUnwrap(lines.firstIndex { $0.contains("tapEnable(tap: click, enable: true)") })
        let effect = try XCTUnwrap(lines.firstIndex { $0.contains("case .enableClickTap:") })
        let nextEffect = try XCTUnwrap(lines[(effect + 1)...].firstIndex {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("case .")
        })
        XCTAssertTrue((effect..<nextEffect).contains(enable),
                      "The click tap is enabled under `case .enableClickTap:` and nowhere else in ClickGuard.")
    }

    /// The window server disables a tap that stopped answering, and says so through the tap itself. That is
    /// the only net there is under a tap whose owner lost the grant, and the callback that re-enabled the tap
    /// on that notice is what cost a hard reboot.
    func testATapIsNeverEnabledFromACallback() throws {
        let source = try code(Self.clickGuard)
        let callbacks = bodies(after: "callback:", in: source)
            + bodies(after: "func sentinelHeard(", in: source)
            + bodies(after: "func clickHeard(", in: source)
        XCTAssertEqual(callbacks.count, 4, "ClickGuard's two callbacks and the two functions they call are gone; move this check with them")
        for callback in callbacks {
            XCTAssertFalse(callback.contains("tapEnable("), """
                A tap callback enables a tap. A tap macOS disabled is never enabled by the event that says so \
                (docs/pitfalls.md 13): what comes back is the next ⇧ Shift press, asked about like any other.
                """)
        }
    }

    /// A notice that a tap was disabled is acted on once the callback that carried it has returned: a tap
    /// disabled or destroyed with its own event still unanswered leaves it to the window server what becomes
    /// of that event.
    func testANoticeThatATapWasDisabledIsHeardAfterItsCallback() throws {
        let source = try code(Self.clickGuard)
        for callback in bodies(after: "func sentinelHeard(", in: source) + bodies(after: "func clickHeard(", in: source) {
            for notice in ["case .tapDisabledByTimeout:", "case .tapDisabledByUserInput:"] {
                let branch = try XCTUnwrap(self.branch(notice, in: callback), "\(notice) is no longer handled")
                XCTAssertTrue(branch.contains("feedAfterThisCallback("), "\(notice) is fed after the callback returns")
                XCTAssertFalse(branch.contains("feed("), "\(notice) is fed inside the callback that carried it")
            }
        }
    }

    func testTheClickTapIsBornDisabledBeforeItIsServed() throws {
        let source = try code(Self.clickGuard)
        let created = try XCTUnwrap(source.range(of: "guard let click = CGEvent.tapCreate("))
        let after = created.upperBound..<source.endIndex
        let disabled = try XCTUnwrap(source.range(of: "CGEvent.tapEnable(tap: click, enable: false)", range: after))
        let served = try XCTUnwrap(source.range(of: "CFRunLoopAddSource(", range: after))
        XCTAssertLessThan(disabled.lowerBound, served.lowerBound, """
            A tap is born enabled. The click tap is disabled in the line after it is created, before its port is \
            on any run loop (docs/macOS.md, The event taps).
            """)
    }

    // MARK: - The taps' thread

    func testTheTapsAreServedOnTheirOwnThread() throws {
        let source = try code(Self.clickGuard)
        XCTAssertTrue(source.contains("TapThread("), "The taps are served by a TapThread.")
        for adding in ["CFRunLoopAddSource(", "CFRunLoopAddTimer("] {
            XCTAssertEqual(source.components(separatedBy: adding).count,
                           source.components(separatedBy: adding + "thread.cfRunLoop").count,
                           "Every \(adding)…) in ClickGuard is on the taps' own run loop.")
        }
        for mainThing in ["CFRunLoopGetMain", "RunLoop.main", "DispatchQueue.main"] {
            XCTAssertFalse(source.contains(mainThing), """
                ClickGuard reaches for \(mainThing). On the main run loop every stall of the interface is a stall \
                of the mouse (docs/architecture.md, Threading).
                """)
        }
    }

    func testTheTapsThreadNeverAsksAnythingThatCanBlock() throws {
        let source = try code(Self.clickGuard)
        for function in ["func feed(", "func run(", "func createTaps(", "func sentinelHeard(", "func clickHeard(",
                         "func startWatchdog(", "func scheduleRechecks("] {
            let body = try XCTUnwrap(bodies(after: function, in: source).first, "\(function) is gone; move this check with it")
            for blocking in ["accessibilityGranted", "AXIsProcessTrusted", "liveVerdict", "AXUIElement"] {
                XCTAssertFalse(body.contains(blocking), """
                    ClickGuard's \(function)…) calls \(blocking) on the taps' thread. It is a round trip with no \
                    timeout while its cache refills, which is when the grant is moving: the worker asks, never the \
                    thread the Mac's clicks wait on (CLAUDE.md, Rules).
                    """)
            }
        }
        let engine = try code("Sources/ShiftPickApp/ShiftPickEngine.swift")
        let probe = try XCTUnwrap(bodies(after: "probeTrust:", in: engine).first)
        XCTAssertTrue(probe.contains("resolver.queue.async"),
                      "The live question about the grant is asked on the worker, and answered from there.")
    }

    // MARK: - One click

    func testAClickReachesTheWorkerOnlyThroughTheDeadline() throws {
        let engine = try code("Sources/ShiftPickApp/ShiftPickEngine.swift")
        XCTAssertEqual(occurrences(of: "resolver.shiftClick(", in: try swiftFiles(under: ["Sources"])).count, 1)
        let gate = try XCTUnwrap(bodies(after: "gate.run(budget: K.clickBudget, grace: K.commitGrace)", in: engine).first,
                                 "A held click is decided through DeadlineGate, with K.clickBudget and K.commitGrace.")
        XCTAssertTrue(gate.contains("resolver.shiftClick("), """
            A held click reaches the worker only inside DeadlineGate.run, which gives it back after K.clickBudget \
            whatever the worker is doing (docs/pitfalls.md 14).
            """)
    }

    func testAClickIsSwallowedOnlyAfterItsSelectionIsSet() throws {
        XCTAssertEqual(occurrences(of: "finish(swallow: true)", in: try swiftFiles(under: ["Sources"])),
                       ["Sources/ShiftPickApp/ShiftClickResolver.swift"],
                       "One line swallows a click, in ShiftClickResolver.shiftClick.")
        let resolver = try code("Sources/ShiftPickApp/ShiftClickResolver.swift")
        let commit = try XCTUnwrap(resolver.range(of: "guard ticket.commit() else"))
        let select = try XCTUnwrap(resolver.range(of: "guard FinderAX.select("))
        let swallow = try XCTUnwrap(resolver.range(of: "ticket.finish(swallow: true)"))
        XCTAssertTrue(commit.lowerBound < select.lowerBound && select.lowerBound < swallow.lowerBound, """
            Fail safe: a click is swallowed after a commit that was granted and a selection that was set, and \
            never otherwise (CLAUDE.md, Rules).
            """)
    }

    // MARK: - Waiting

    /// The waits with no deadline are known, and none is where a click or the main thread waits on it.
    func testWaitsWithoutADeadlineStayWhereTheyAre() throws {
        let sources = try swiftFiles(under: ["Sources"])
        // TapThread's two: its own start, and a block that has already started running on it.
        XCTAssertEqual(Set(occurrences(of: ".wait()", in: sources)), ["Sources/ShiftPickPlatform/TapThread.swift"],
                       "A new wait with no deadline. Nothing here blocks without a timeout (CLAUDE.md, Rules).")
        // The update's staging runs on a queue of its own, never the main thread.
        XCTAssertEqual(occurrences(of: "waitUntilExit", in: sources), ["Sources/ShiftPickPlatform/UpdateStager.swift"], """
            Process.waitUntilExit() runs the calling thread's run loop and has no deadline; on the main thread it \
            froze the uninstall (docs/pitfalls.md 16). Wait through BoundedWait, off the main thread.
            """)
        XCTAssertEqual(occurrences(of: "DispatchQueue.main.sync", in: sources), [],
                       "Nothing blocks on the main thread, and nothing blocks another thread on it.")
    }

    // MARK: - Taking the grant or the process away

    func testTheUninstallStopsTheTapsBeforeItTakesTheGrant() throws {
        let page = try code("Sources/ShiftPickApp/SettingsGeneralPage.swift")
        let shutDown = try XCTUnwrap(page.range(of: "engine.shutDown()"))
        let offMain = try XCTUnwrap(page.range(of: "DispatchQueue.global("))
        let registrations = try XCTUnwrap(page.range(of: "Uninstall.removeSystemRegistrations()"))
        XCTAssertTrue(shutDown.lowerBound < offMain.lowerBound && offMain.lowerBound < registrations.lowerBound, """
            The uninstall destroys both taps before anything takes the grant away, and waits for the system off \
            the main thread (docs/functional.md §9).
            """)
        XCTAssertEqual(Set(occurrences(of: "tccutil", in: try swiftFiles(under: ["Sources"]))),
                       ["Sources/ShiftPickPlatform/Uninstall.swift"], "Only the uninstall takes the grant away.")
        let uninstall = try code("Sources/ShiftPickPlatform/Uninstall.swift")
        XCTAssertTrue(uninstall.contains("dispatchPrecondition(condition: .notOnQueue(.main))"),
                      "Uninstall.removeSystemRegistrations refuses to run on the main thread.")
        XCTAssertTrue(uninstall.contains("BoundedWait.run(\"/usr/bin/tccutil\""),
                      "tccutil is waited for with a deadline.")
    }

    func testAQuitTearsTheTapsDownFirst() throws {
        let delegate = try code("Sources/ShiftPickApp/AppDelegate.swift")
        let quit = try XCTUnwrap(bodies(after: "func applicationWillTerminate(", in: delegate).first)
        XCTAssertTrue(quit.contains("engine.shutDown()"), "A quit destroys both taps before anything else happens.")
    }

    // MARK: - Around the taps

    /// The breaker is closed by the user asking, and by nothing else: one button, through the engine, and
    /// the engine alone talks to the guard about it.
    func testAnotherTryIsAskedForThroughTheEngineAlone() throws {
        let sources = try swiftFiles(under: ["Sources"])
        XCTAssertEqual(occurrences(of: "clickGuard.tryAgain()", in: sources), ["Sources/ShiftPickApp/ShiftPickEngine.swift"],
                       "Only ShiftPickEngine.tryAgain asks the guard for another try (docs/functional.md §1).")
        XCTAssertEqual(occurrences(of: "engine.tryAgain()", in: sources), ["Sources/ShiftPickApp/SettingsSystemPage.swift"],
                       "Only the System page's Start Listening Again button asks the engine.")
    }

    func testOnlyAButtonAsksForThePermission() throws {
        let sources = try swiftFiles(under: ["Sources"])
        XCTAssertEqual(Set(occurrences(of: "AXIsProcessTrustedWithOptions", in: sources)),
                       ["Sources/ShiftPickPlatform/Permissions.swift"], "Permissions.requestAccessibility is the only way to ask.")
        XCTAssertEqual(occurrences(of: "Permissions.requestAccessibility()", in: sources),
                       ["Sources/ShiftPickApp/GrantCatalogue.swift"],
                       "Every permission prompt follows a click of the user's: the wizard's row asks, and nothing else.")
    }

    func testASecondCopyLeavesBeforeItCreatesAnything() throws {
        let main = try code("Sources/ShiftPickApp/ShiftPickMain.swift")
        let leave = try XCTUnwrap(main.range(of: "leaveIfAlreadyRunning()"))
        let app = try XCTUnwrap(main.range(of: "NSApplication.shared"))
        XCTAssertLessThan(leave.lowerBound, app.lowerBound, "Two copies are two taps on the same clicks.")
    }

    func testTheLaunchWatchesTheGrantTheSessionAndASecondCopy() throws {
        let delegate = try code("Sources/ShiftPickApp/AppDelegate.swift")
        let launch = try XCTUnwrap(bodies(after: "func applicationDidFinishLaunching(", in: delegate).first)
        for watch in ["watchTheGrant()", "watchTheSession()", "watchForASecondCopy()"] {
            XCTAssertTrue(launch.contains(watch), """
                The launch no longer calls \(watch). The grant's notification disarms first, sleep and the lock \
                screen suspend, and a second copy is answered (docs/functional.md §1 and §7).
                """)
        }
    }

    /// The reasons a Mac is away are `Core/AwayReasons`, which `AwayReasonsTests` pins; the delegate feeds
    /// it and does what it says. A set of the delegate's own, looked at only once it was empty, is what left
    /// the engine suspended for good with every window saying it was listening (docs/pitfalls.md 17).
    func testTheSessionIsReconciledThroughOneValue() throws {
        let path = "Sources/ShiftPickApp/AppDelegate.swift"
        let delegate = try code(path)
        XCTAssertTrue(delegate.contains("AwayReasons()"), """
            AppDelegate no longer holds Core/AwayReasons. The reasons a Mac is away, and when the engine is \
            suspended and resumed for them, are decided there as a value and pinned by AwayReasonsTests \
            (docs/functional.md §1; docs/pitfalls.md 17).
            """)
        let run = try XCTUnwrap(bodies(after: "func run(_ effects: [AwayReasons.Effect])", in: delegate).first,
                                "AppDelegate.run(_:) is what does what AwayReasons decided.")
        for call in ["engine.suspend()", "engine.resume()"] {
            XCTAssertEqual(occurrences(of: call, in: [(path: path, code: delegate)]), [path], """
                \(call) is called once in AppDelegate, in run(_:), under the effect AwayReasons decided. A second \
                call is a way for the engine's state and the reasons to disagree (docs/pitfalls.md 17).
                """)
            XCTAssertTrue(run.contains(call), "\(call) is done in run(_:), under AwayReasons' effect.")
        }
    }

    func testWindowsShowTheGrantThroughOneRule() throws {
        let catalogue = try code("Sources/ShiftPickApp/GrantCatalogue.swift")
        XCTAssertTrue(catalogue.contains("granted: grantIsInPlace") && !catalogue.contains("Permissions.accessibilityGranted"), """
            The wizard's row reads macOS's cached answer alone, which was measured saying yes for seconds after \
            the grant had gone. Rows show TapLifecycle.Status.showsGrant (docs/macOS.md, The permission).
            """)
        for window in ["Sources/ShiftPickApp/AppDelegate.swift", "Sources/ShiftPickApp/SettingsSystemPage.swift",
                       "Sources/ShiftPickApp/SettingsHealthPage.swift", "Sources/ShiftPickApp/MenuBarController.swift"] {
            XCTAssertTrue(try code(window).contains("showsGrant(systemSays:"), "\(window) shows the grant through showsGrant.")
        }
    }

    // MARK: - The numbers keep their order

    func testTheSafetyNumbersKeepTheirOrder() {
        XCTAssertLessThan(K.axTimeout, K.clickBudget,
                          "One Accessibility call that never answers cannot spend a click's whole budget.")
        XCTAssertLessThanOrEqual(K.commitGrace, K.axTimeout,
                                 "The grace waits for one call, and for no longer than that call may take.")
        XCTAssertLessThan(K.clickBudget + K.commitGrace, 0.5,
                          "The longest a held click waits stays far under the time after which macOS takes a tap away.")
        XCTAssertGreaterThanOrEqual(K.shutDownWait, K.clickBudget + K.commitGrace,
                                    "A teardown waits at least as long as the taps' thread can be busy with one click.")
        XCTAssertLessThan(K.trustProbeTimeout, K.armedWatchInterval,
                          "A look's live question is answered, or given up on, before the next look.")
        XCTAssertTrue((1...3).contains(K.breakerTrips),
                      "Each trip is a click the window server waited on; three is the most ShiftPick spends before it stops.")
        XCTAssertLessThanOrEqual(K.armedIdleLimit, 60, "A key held down by a bag does not keep the click tap enabled.")
        XCTAssertLessThanOrEqual(K.trustFreshness, 2, "Arming reuses a live answer about the grant for two seconds at most.")
        XCTAssertTrue((1...30).contains(K.uninstallStepWait), "An uninstall step is waited for, and then given up on.")
    }

    // MARK: - Reading the source

    /// A file's text without its comment lines, so that a rule quoted in a comment is not taken for code.
    private func code(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func swiftFiles(under directories: [String]) throws -> [(path: String, code: String)] {
        var files: [(path: String, code: String)] = []
        for directory in directories {
            let base = Self.root.appendingPathComponent(directory)
            guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let path = String(url.path.dropFirst(Self.root.path.count + 1))
                let text = try code(path)
                files.append((path: path, code: text))
            }
        }
        XCTAssertFalse(files.isEmpty, "no sources were found under \(Self.root.path)")
        return files.sorted { $0.path < $1.path }
    }

    /// The file of every occurrence of `needle`, once per occurrence.
    private func occurrences(of needle: String, in files: [(path: String, code: String)]) -> [String] {
        files.flatMap { file in
            Array(repeating: file.path, count: file.code.components(separatedBy: needle).count - 1)
        }
    }

    /// For every occurrence of `anchor`, the braces that open after it and everything up to the one that
    /// closes them: a function's body, a closure's, a call's trailing closure.
    private func bodies(after anchor: String, in code: String) -> [String] {
        var found: [String] = []
        var searchFrom = code.startIndex
        while let hit = code.range(of: anchor, range: searchFrom..<code.endIndex) {
            searchFrom = hit.upperBound
            guard let open = code.range(of: "{", range: hit.upperBound..<code.endIndex) else { break }
            var depth = 0
            var index = open.lowerBound
            while index < code.endIndex {
                if code[index] == "{" { depth += 1 }
                if code[index] == "}" {
                    depth -= 1
                    if depth == 0 { found.append(String(code[open.lowerBound...index])); break }
                }
                index = code.index(after: index)
            }
        }
        return found
    }

    /// The lines of a `switch` branch: from `label` to the next `case` or `default` at any depth.
    private func branch(_ label: String, in body: String) -> String? {
        guard let start = body.range(of: label) else { return nil }
        let rest = body[start.upperBound...]
        let ends = ["case .", "default:"].compactMap { rest.range(of: $0)?.lowerBound }
        return String(rest[..<(ends.min() ?? rest.endIndex)])
    }
}
