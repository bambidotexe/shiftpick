import XCTest
import ShiftPickCore

/// When the click tap may be enabled, and what every event does to it. The click tap is the one object in
/// the app that can hold up the Mac's input, so every rule about it is pinned here.
final class TapLifecycleTests: XCTestCase {
    private typealias Effect = TapLifecycle.Effect

    private var life = TapLifecycle(userEnabled: true)
    private var now: TimeInterval = 1_000

    /// What the event made the app do, without the log lines.
    @discardableResult
    private func send(_ event: TapLifecycle.Event, after seconds: TimeInterval = 0) -> [Effect] {
        now += seconds
        return life.handle(event, now: now).filter {
            if case .log = $0 { return false }
            return true
        }
    }

    /// The generation of the live question `effects` asks, which its answer has to carry back.
    private func generation(in effects: [Effect]) -> Int? {
        for case .probeTrust(let generation) in effects { return generation }
        return nil
    }

    /// Answers the live question `asked` holds, and fails the test rather than the bundle when it holds none.
    @discardableResult
    private func answer(_ asked: [Effect], _ verdict: TrustVerdict,
                        file: StaticString = #filePath, line: UInt = #line) -> [Effect] {
        guard let generation = generation(in: asked) else {
            XCTFail("no live question was asked", file: file, line: line)
            return []
        }
        return send(.trustProbe(verdict, generation: generation))
    }

    private func pressShift() -> [Effect] { send(.modifiers(shift: true, optionOrControl: false)) }
    private func releaseShift() -> [Effect] { send(.modifiers(shift: false, optionOrControl: false)) }

    /// Launched with the grant, the taps created: where a running app spends its life.
    private func startWatching() {
        send(.start(trusted: true))
        send(.tapsCreated(true))
    }

    /// ⇧ Shift down and the live question answered: the click tap is enabled.
    private func arm() {
        startWatching()
        let asked = pressShift()
        answer(asked, .trusted)
        XCTAssertEqual(life.phase, .armed)
    }

    // MARK: - Starting

    func testNothingIsCreatedWithoutTheGrant() {
        XCTAssertEqual(send(.start(trusted: false)), [.report(.needsPermission)])
        XCTAssertEqual(life.phase, .off(.needsPermission))
    }

    func testTheGrantCreatesTheTapsAndEnablesNoClickTap() {
        XCTAssertEqual(send(.start(trusted: true)), [.createTaps])
        XCTAssertEqual(send(.tapsCreated(true)), [.report(.watching)])
        XCTAssertEqual(life.phase, .idle)
    }

    func testATapMacOSWouldNotCreateIsSaidSo() {
        send(.start(trusted: true))
        XCTAssertEqual(send(.tapsCreated(false)), [.report(.refused)])
        XCTAssertEqual(life.phase, .off(.refused))
    }

    func testStartingTwiceCreatesNothingTwice() {
        startWatching()
        XCTAssertEqual(send(.start(trusted: true)), [])
        XCTAssertEqual(life.phase, .idle)
    }

    // MARK: - Arming

    func testTheFirstShiftPressAsksBeforeItArms() {
        startWatching()
        let effects = pressShift()
        XCTAssertNotNil(generation(in: effects))
        XCTAssertFalse(effects.contains(.enableClickTap))
        XCTAssertEqual(life.phase, .arming)
    }

    func testATrustedAnswerArms() {
        startWatching()
        let asked = pressShift()
        let effects = answer(asked, .trusted)
        XCTAssertEqual(effects, [.enableClickTap, .startWatchdog])
        XCTAssertEqual(life.phase, .armed)
    }

    func testAnAnswerStillFreshArmsAtOnce() {
        arm()
        _ = releaseShift()
        now += K.trustFreshness - 0.1
        XCTAssertEqual(pressShift(), [.enableClickTap, .startWatchdog])
    }

    func testAnAnswerGoneStaleIsAskedAgain() {
        arm()
        _ = releaseShift()
        now += K.trustFreshness + 0.1
        let effects = pressShift()
        XCTAssertNotNil(generation(in: effects))
        XCTAssertFalse(effects.contains(.enableClickTap))
    }

    func testReleasingShiftDisarms() {
        arm()
        XCTAssertEqual(releaseShift(), [.disableClickTap, .stopWatchdog])
        XCTAssertEqual(life.phase, .idle)
    }

    func testReleasingShiftBeforeTheAnswerArmsNothing() {
        startWatching()
        let asked = pressShift()
        _ = releaseShift()
        XCTAssertEqual(answer(asked, .trusted), [])
        XCTAssertEqual(life.phase, .idle)
    }

    /// An answer that was asked for before the privacy database moved says nothing about it now.
    func testAnAnswerToAnOlderQuestionArmsNothing() {
        startWatching()
        guard let first = generation(in: pressShift()) else { return XCTFail("no live question was asked") }
        let again = send(.trustNotification)
        XCTAssertNotNil(generation(in: again))
        XCTAssertNotEqual(generation(in: again), first)
        XCTAssertEqual(send(.trustProbe(.trusted, generation: first)), [])
        XCTAssertEqual(life.phase, .arming)
    }

    func testAnAnswerThatNeverCameArmsNothing() {
        startWatching()
        let asked = pressShift()
        XCTAssertEqual(answer(asked, .unknown), [])
        XCTAssertEqual(life.phase, .idle)
    }

    func testOptionOrControlNeverArms() {
        startWatching()
        XCTAssertEqual(send(.modifiers(shift: true, optionOrControl: true)), [])
        XCTAssertEqual(life.phase, .idle)
    }

    func testTheKillSwitchArmsNothing() {
        startWatching()
        send(.userEnabled(false))
        XCTAssertEqual(pressShift(), [])
        XCTAssertEqual(life.phase, .idle)
    }

    func testTurningShiftPickOffWhileArmedDisarms() {
        arm()
        XCTAssertEqual(send(.userEnabled(false)), [.disableClickTap, .stopWatchdog])
        XCTAssertEqual(life.phase, .idle)
    }

    // MARK: - macOS takes the tap away

    /// The defect that cost a hard reboot: macOS disabled the stalled tap three times and the callback
    /// enabled it again three times. Whatever else this event does, it never enables anything.
    func testATapMacOSDisabledIsNeverReEnabledByThatEvent() {
        for reason in [TapLifecycle.DisableReason.timeout, .userInput, .wouldNotEnable] {
            life = TapLifecycle(userEnabled: true)
            arm()
            let effects = send(.tapDisabledBySystem(.click, reason))
            XCTAssertFalse(effects.contains(.enableClickTap), "\(reason)")
            XCTAssertTrue(effects.contains(.stopWatchdog), "\(reason)")
            XCTAssertEqual(life.phase, .idle, "\(reason)")
        }
    }

    /// A timeout is what a revoked grant looks like from the inside, so it is looked into.
    func testATripLooksAtTheGrantAgain() {
        arm()
        XCTAssertTrue(send(.tapDisabledBySystem(.click, .timeout)).contains(.recheckTrustSoon))
    }

    func testATripIsLoggedAsAnError() {
        arm()
        now += 1
        let logged = life.handle(.tapDisabledBySystem(.click, .timeout), now: now).contains {
            if case .log(.error, _) = $0 { return true }
            return false
        }
        XCTAssertTrue(logged)
    }

    func testAfterATripTheNextPressAsksAgainHoweverFreshTheLastAnswerWas() {
        arm()
        send(.tapDisabledBySystem(.click, .timeout))
        let effects = pressShift()
        XCTAssertNotNil(generation(in: effects))
        XCTAssertFalse(effects.contains(.enableClickTap))
    }

    func testThreeTripsInsideTheWindowOpenTheBreaker() {
        arm()
        for _ in 1..<K.breakerTrips {
            send(.tapDisabledBySystem(.click, .timeout), after: 1)
            let asked = pressShift()
            answer(asked, .trusted)
        }
        let effects = send(.tapDisabledBySystem(.click, .timeout), after: 1)
        XCTAssertTrue(effects.contains(.destroyTaps))
        XCTAssertTrue(effects.contains(.report(.breakerOpen)))
        XCTAssertFalse(effects.contains(.enableClickTap))
        XCTAssertEqual(life.phase, .off(.breakerOpen))
    }

    func testTripsSpreadOverMoreThanTheWindowOpenNothing() {
        arm()
        for _ in 0..<(K.breakerTrips + 2) {
            send(.tapDisabledBySystem(.click, .timeout), after: K.breakerWindow)
            let asked = pressShift()
            answer(asked, .trusted)
        }
        XCTAssertEqual(life.phase, .armed)
    }

    func testAnOpenBreakerArmsNothing() {
        arm()
        for _ in 0..<K.breakerTrips { send(.tapDisabledBySystem(.click, .timeout), after: 1) }
        XCTAssertEqual(life.phase, .off(.breakerOpen))
        XCTAssertEqual(pressShift(), [])
    }

    /// A launch, a grant that arrives, a poll that finds the grant in place: all of them start, and none of
    /// them is somebody asking for another try. Only that closes the breaker.
    func testAnOrdinaryStartLeavesTheBreakerOpen() {
        arm()
        for _ in 0..<K.breakerTrips { send(.tapDisabledBySystem(.click, .timeout), after: 1) }
        XCTAssertEqual(send(.start(trusted: true)), [])
        XCTAssertEqual(send(.trustRecheck(.trusted)), [])
        XCTAssertEqual(life.phase, .off(.breakerOpen))
    }

    func testAskingForAnotherTryClosesTheBreaker() {
        arm()
        for _ in 0..<K.breakerTrips { send(.tapDisabledBySystem(.click, .timeout), after: 1) }
        XCTAssertEqual(send(.tryAgain(trusted: true)), [.createTaps])
        send(.tapsCreated(true))
        // The count starts over too: one more trip is one trip.
        let asked = pressShift()
        answer(asked, .trusted)
        send(.tapDisabledBySystem(.click, .timeout))
        XCTAssertEqual(life.phase, .idle)
    }

    /// The sentinel cannot hold anything up, but enabling it again blindly is the same habit.
    func testTheSentinelIsOnlyEnabledAgainAfterALiveAnswer() {
        startWatching()
        let effects = send(.tapDisabledBySystem(.sentinel, .timeout))
        XCTAssertFalse(effects.contains(.enableSentinel))
        XCTAssertEqual(answer(effects, .trusted), [.enableSentinel])
    }

    func testLosingTheSentinelWhileArmedDisarms() {
        arm()
        let effects = send(.tapDisabledBySystem(.sentinel, .userInput))
        XCTAssertTrue(effects.contains(.disableClickTap))
        XCTAssertTrue(effects.contains(.stopWatchdog))
        XCTAssertEqual(life.phase, .idle)
    }

    func testAnotherTryWithoutTheGrantWaitsForIt() {
        arm()
        for _ in 0..<K.breakerTrips { send(.tapDisabledBySystem(.click, .timeout), after: 1) }
        XCTAssertEqual(send(.tryAgain(trusted: false)), [.report(.needsPermission)])
        XCTAssertEqual(life.phase, .off(.needsPermission))
    }

    func testAnotherTryWithNothingBrokenIsNothing() {
        startWatching()
        XCTAssertEqual(send(.tryAgain(trusted: true)), [])
        XCTAssertEqual(life.phase, .idle)
    }

    // MARK: - The grant

    func testARevokedAnswerTakesEverythingDown() {
        startWatching()
        let asked = pressShift()
        let effects = answer(asked, .revoked)
        XCTAssertEqual(effects, [.destroyTaps, .report(.needsPermission)])
        XCTAssertEqual(life.phase, .off(.needsPermission))
    }

    /// `revoked` is the system saying so, and no question is too old for that answer.
    func testARevokedAnswerIsBelievedWhateverQuestionItAnswers() {
        arm()
        let effects = send(.trustProbe(.revoked, generation: -7))
        XCTAssertEqual(effects, [.disableClickTap, .stopWatchdog, .destroyTaps, .report(.needsPermission)])
    }

    func testTheGrantGoingWhileArmedDisarmsBeforeItDestroys() {
        arm()
        XCTAssertEqual(send(.trustLost),
                       [.disableClickTap, .stopWatchdog, .destroyTaps, .report(.needsPermission)])
        XCTAssertEqual(life.phase, .off(.needsPermission))
    }

    func testTheGrantGoingTwiceIsSaidOnce() {
        startWatching()
        send(.trustLost)
        XCTAssertEqual(send(.trustLost), [])
    }

    /// The privacy database moved. It may not be about this app at all, so the tap goes first and the
    /// question comes after: the other order is a tap left enabled while the answer is fetched.
    func testTheNotificationDisarmsBeforeItAsks() {
        arm()
        let effects = send(.trustNotification)
        XCTAssertEqual(Array(effects.prefix(2)), [.disableClickTap, .stopWatchdog])
        XCTAssertNotNil(generation(in: effects))
        XCTAssertTrue(effects.contains(.recheckTrustSoon))
        XCTAssertEqual(life.phase, .arming)
    }

    func testTheNotificationMakesTheNextPressAskAgain() {
        arm()
        _ = releaseShift()
        send(.trustNotification)
        let effects = pressShift()
        XCTAssertNotNil(generation(in: effects))
        XCTAssertFalse(effects.contains(.enableClickTap))
    }

    func testTheNotificationWhileWaitingForTheGrantLooksAgain() {
        send(.start(trusted: false))
        XCTAssertEqual(send(.trustNotification), [.recheckTrustSoon])
    }

    func testTheGrantFoundByLookingAgainCreatesTheTaps() {
        send(.start(trusted: false))
        XCTAssertEqual(send(.trustRecheck(.trusted)), [.createTaps])
    }

    func testLookingAgainAndFindingTheGrantGoneTakesEverythingDown() {
        startWatching()
        XCTAssertEqual(send(.trustRecheck(.revoked)), [.destroyTaps, .report(.needsPermission)])
    }

    func testLookingAgainAndFindingNobodyHomeChangesNothing() {
        startWatching()
        XCTAssertEqual(send(.trustRecheck(.unknown)), [])
        XCTAssertEqual(life.phase, .idle)
    }

    // MARK: - A swallowed press and its release

    func testASwallowedPressKeepsTheTapArmedUntilItsRelease() {
        arm()
        send(.pressDecided(number: 41, swallowed: true))
        XCTAssertEqual(releaseShift(), [])
        XCTAssertEqual(life.phase, .armed)
        XCTAssertTrue(life.shouldSwallowRelease(41))
        XCTAssertEqual(send(.releaseSeen(number: 41)), [.disableClickTap, .stopWatchdog])
        XCTAssertEqual(life.phase, .idle)
    }

    func testTheReleaseWithShiftStillDownStaysArmed() {
        arm()
        send(.pressDecided(number: 41, swallowed: true))
        XCTAssertEqual(send(.releaseSeen(number: 41)), [])
        XCTAssertEqual(life.phase, .armed)
        XCTAssertFalse(life.shouldSwallowRelease(41))
    }

    func testOnlyTheReleaseOfTheSwallowedPressIsSwallowed() {
        arm()
        send(.pressDecided(number: 41, swallowed: true))
        XCTAssertFalse(life.shouldSwallowRelease(42))
    }

    /// A release that never arrives cannot swallow somebody else's.
    func testAPressThatWasLetThroughForgetsTheOneBefore() {
        arm()
        send(.pressDecided(number: 41, swallowed: true))
        send(.pressDecided(number: 42, swallowed: false))
        XCTAssertFalse(life.shouldSwallowRelease(41))
        XCTAssertFalse(life.shouldSwallowRelease(42))
    }

    func testATripForgetsTheSwallowedPress() {
        arm()
        send(.pressDecided(number: 41, swallowed: true))
        send(.tapDisabledBySystem(.click, .timeout))
        XCTAssertFalse(life.shouldSwallowRelease(41))
    }

    // MARK: - The watch kept while armed

    func testAWatchWithEverythingInOrderAsksAboutTheGrant() {
        arm()
        let effects = send(.watchdog(shiftDown: true, buttonDown: false, trusted: true), after: 0.5)
        XCTAssertNotNil(generation(in: effects))
        XCTAssertEqual(life.phase, .armed)
    }

    /// A release the sentinel never heard.
    func testTheWatchDisarmsWhenShiftIsNoLongerDown() {
        arm()
        XCTAssertEqual(send(.watchdog(shiftDown: false, buttonDown: false, trusted: true)),
                       [.disableClickTap, .stopWatchdog])
        XCTAssertEqual(life.phase, .idle)
    }

    func testTheWatchWaitsForTheReleaseOfASwallowedPress() {
        arm()
        send(.pressDecided(number: 41, swallowed: true))
        let effects = send(.watchdog(shiftDown: false, buttonDown: true, trusted: true))
        XCTAssertFalse(effects.contains(.disableClickTap))
        XCTAssertEqual(life.phase, .armed)
    }

    func testTheWatchStopsWaitingOnceTheButtonIsUp() {
        arm()
        send(.pressDecided(number: 41, swallowed: true))
        XCTAssertEqual(send(.watchdog(shiftDown: false, buttonDown: false, trusted: true)),
                       [.disableClickTap, .stopWatchdog])
        XCTAssertFalse(life.shouldSwallowRelease(41))
    }

    func testTheWatchTakesEverythingDownWhenTheGrantReadsGone() {
        arm()
        XCTAssertEqual(send(.watchdog(shiftDown: true, buttonDown: false, trusted: false)),
                       [.disableClickTap, .stopWatchdog, .destroyTaps, .report(.needsPermission)])
    }

    /// A key held down by a bag, or latched by Sticky Keys.
    func testTheWatchDisarmsAfterTheIdleLimit() {
        arm()
        XCTAssertEqual(send(.watchdog(shiftDown: true, buttonDown: false, trusted: true),
                            after: K.armedIdleLimit + 1),
                       [.disableClickTap, .stopWatchdog])
        XCTAssertEqual(life.phase, .idle)
    }

    func testAClickStartsTheIdleLimitOver() {
        arm()
        send(.pressDecided(number: 41, swallowed: false), after: K.armedIdleLimit - 1)
        send(.watchdog(shiftDown: true, buttonDown: false, trusted: true), after: 2)
        XCTAssertEqual(life.phase, .armed)
    }

    func testAnAnswerThatNeverCameWhileArmedDisarms() {
        arm()
        let asked = send(.watchdog(shiftDown: true, buttonDown: false, trusted: true), after: 0.5)
        XCTAssertEqual(answer(asked, .unknown),
                       [.disableClickTap, .stopWatchdog])
        XCTAssertEqual(life.phase, .idle)
    }

    func testAStrayWatchStopsItself() {
        startWatching()
        XCTAssertEqual(send(.watchdog(shiftDown: true, buttonDown: false, trusted: true)), [.stopWatchdog])
    }

    // MARK: - Sleep, the lock screen, another user's session

    func testSuspendingDisarms() {
        arm()
        XCTAssertEqual(send(.suspend), [.disableClickTap, .stopWatchdog])
        XCTAssertEqual(life.phase, .suspended)
    }

    func testNothingArmsWhileSuspended() {
        startWatching()
        send(.suspend)
        XCTAssertEqual(pressShift(), [])
        XCTAssertEqual(life.phase, .suspended)
    }

    func testResumingListensAgainAndAsksBeforeTheNextArming() {
        arm()
        send(.suspend)
        XCTAssertEqual(send(.resume(trusted: true)), [.enableSentinel])
        XCTAssertEqual(life.phase, .idle)
        XCTAssertNotNil(generation(in: pressShift()))
    }

    func testResumingWithoutTheGrantTakesEverythingDown() {
        startWatching()
        send(.suspend)
        XCTAssertEqual(send(.resume(trusted: false)), [.destroyTaps, .report(.needsPermission)])
    }

    func testSuspendingWithNoTapsIsNothing() {
        send(.start(trusted: false))
        XCTAssertEqual(send(.suspend), [])
        XCTAssertEqual(life.phase, .off(.needsPermission))
    }

    // MARK: - The end

    func testTerminatingWhileArmedDisarmsThenDestroys() {
        arm()
        XCTAssertEqual(send(.terminate), [.disableClickTap, .stopWatchdog, .destroyTaps, .report(.stopped)])
        XCTAssertEqual(life.phase, .off(.terminated))
    }

    func testTerminatingIsFinal() {
        arm()
        send(.terminate)
        XCTAssertEqual(send(.start(trusted: true)), [])
        XCTAssertEqual(pressShift(), [])
        XCTAssertEqual(send(.trustRecheck(.trusted)), [])
        XCTAssertEqual(life.phase, .off(.terminated))
    }

    // MARK: - What the windows are told

    func testTheStatusOfEveryPhase() {
        XCTAssertEqual(life.status, .stopped)
        startWatching()
        XCTAssertEqual(life.status, .watching)
        _ = pressShift()
        XCTAssertEqual(life.status, .watching)
        send(.suspend)
        XCTAssertEqual(life.status, .watching)
        send(.resume(trusted: false))
        XCTAssertEqual(life.status, .needsPermission)
    }

    /// Arming and disarming happen at every capital letter. None of it is news.
    func testArmingIsNotReported() {
        startWatching()
        let asked = pressShift()
        let effects = answer(asked, .trusted) + releaseShift()
        XCTAssertFalse(effects.contains { if case .report = $0 { return true } else { return false } })
    }
}
