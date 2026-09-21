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

    /// macOS disabling a tap that has stopped answering is the system's own safety net, and enabling the tap
    /// again from that event cuts it (`docs/pitfalls.md` 13). Whatever else this event does, it never
    /// enables anything.
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
        // Asked for, and still only on a live answer: a breaker that opened because the grant had gone is
        // not closed on the cached answer that missed it.
        let again = send(.tryAgain(trusted: true))
        XCTAssertFalse(again.contains(.createTaps))
        XCTAssertEqual(answer(again, .trusted), [.createTaps])
        send(.tapsCreated(true))
        // The count starts over too: one more trip is one trip.
        answer(pressShift(), .trusted)
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
        let effects = send(.watchdog(shiftDown: true, buttonDown: false), after: 0.5)
        XCTAssertNotNil(generation(in: effects))
        XCTAssertEqual(life.phase, .armed)
    }

    /// A release the sentinel never heard.
    func testTheWatchDisarmsWhenShiftIsNoLongerDown() {
        arm()
        XCTAssertEqual(send(.watchdog(shiftDown: false, buttonDown: false)),
                       [.disableClickTap, .stopWatchdog])
        XCTAssertEqual(life.phase, .idle)
    }

    func testTheWatchWaitsForTheReleaseOfASwallowedPress() {
        arm()
        send(.pressDecided(number: 41, swallowed: true))
        let effects = send(.watchdog(shiftDown: false, buttonDown: true))
        XCTAssertFalse(effects.contains(.disableClickTap))
        XCTAssertEqual(life.phase, .armed)
    }

    func testTheWatchStopsWaitingOnceTheButtonIsUp() {
        arm()
        send(.pressDecided(number: 41, swallowed: true))
        XCTAssertEqual(send(.watchdog(shiftDown: false, buttonDown: false)),
                       [.disableClickTap, .stopWatchdog])
        XCTAssertFalse(life.shouldSwallowRelease(41))
    }

    /// The watch asks the live question and nothing else about the grant: the cached answer is not read on
    /// the thread the Mac's clicks are waiting on.
    func testTheWatchsQuestionComingBackRefusedTakesEverythingDown() {
        arm()
        let asked = send(.watchdog(shiftDown: true, buttonDown: false), after: 0.5)
        XCTAssertEqual(answer(asked, .revoked),
                       [.disableClickTap, .stopWatchdog, .destroyTaps, .report(.needsPermission)])
    }

    /// A key held down by a bag, or latched by Sticky Keys.
    func testTheWatchDisarmsAfterTheIdleLimit() {
        arm()
        XCTAssertEqual(send(.watchdog(shiftDown: true, buttonDown: false),
                            after: K.armedIdleLimit + 1),
                       [.disableClickTap, .stopWatchdog])
        XCTAssertEqual(life.phase, .idle)
    }

    func testAClickStartsTheIdleLimitOver() {
        arm()
        send(.pressDecided(number: 41, swallowed: false), after: K.armedIdleLimit - 1)
        send(.watchdog(shiftDown: true, buttonDown: false), after: 2)
        XCTAssertEqual(life.phase, .armed)
    }

    func testAnAnswerThatNeverCameWhileArmedDisarms() {
        arm()
        let asked = send(.watchdog(shiftDown: true, buttonDown: false), after: 0.5)
        XCTAssertEqual(answer(asked, .unknown),
                       [.disableClickTap, .stopWatchdog])
        XCTAssertEqual(life.phase, .idle)
    }

    func testAStrayWatchStopsItself() {
        startWatching()
        XCTAssertEqual(send(.watchdog(shiftDown: true, buttonDown: false)), [.stopWatchdog])
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

    // MARK: - Only while the keys ask for it

    /// The privacy database moves between a swallowed press and its release, with ⇧ Shift already up. The
    /// tap was only still armed for that release, so there is nothing to arm again for.
    func testANotificationWhileWaitingForAReleaseDoesNotArmAgainWithShiftUp() {
        arm()
        send(.pressDecided(number: 41, swallowed: true))
        _ = releaseShift()
        XCTAssertEqual(life.phase, .armed)
        let effects = send(.trustNotification)
        XCTAssertEqual(Array(effects.prefix(2)), [.disableClickTap, .stopWatchdog])
        XCTAssertNil(generation(in: effects), "nothing is asked on behalf of a key that is up")
        XCTAssertEqual(life.phase, .idle)
    }

    func testATrustedAnswerArmsNothingOnceTheKeyIsUp() {
        startWatching()
        guard let asked = generation(in: pressShift()) else { return XCTFail("no live question was asked") }
        send(.modifiers(shift: true, optionOrControl: true))
        XCTAssertEqual(send(.trustProbe(.trusted, generation: asked)), [])
        XCTAssertNotEqual(life.phase, .armed)
    }

    /// ⌥ Option or ⌃ Control going down after ⇧ Shift: the click would be Finder's, so the tap has no
    /// business being enabled for it.
    func testOptionOrControlGoingDownWhileArmedDisarms() {
        arm()
        XCTAssertEqual(send(.modifiers(shift: true, optionOrControl: true)), [.disableClickTap, .stopWatchdog])
        XCTAssertEqual(life.phase, .idle)
    }

    func testLettingGoOfOptionWithShiftStillDownArmsAgain() {
        arm()
        send(.modifiers(shift: true, optionOrControl: true))
        XCTAssertEqual(pressShift(), [.enableClickTap, .startWatchdog])
    }

    // MARK: - An answer is only as good as the moment it was asked

    /// A question asked before the grant was put in doubt says nothing about it afterwards, whichever way
    /// the doubt arrived. The watch asks every half second while armed, so there is nearly always one in flight.
    func testAnAnswerAskedBeforeTheNotificationVouchesForNothingAfterIt() {
        arm()
        guard let inFlight = generation(in: send(.watchdog(shiftDown: true, buttonDown: false), after: 0.5))
        else { return XCTFail("the watch asked nothing") }
        _ = releaseShift()
        send(.trustNotification)
        XCTAssertEqual(send(.trustProbe(.trusted, generation: inFlight)), [])
        let effects = pressShift()
        XCTAssertNotNil(generation(in: effects))
        XCTAssertFalse(effects.contains(.enableClickTap))
    }

    func testAnAnswerAskedBeforeATripVouchesForNothingAfterIt() {
        arm()
        guard let inFlight = generation(in: send(.watchdog(shiftDown: true, buttonDown: false), after: 0.5))
        else { return XCTFail("the watch asked nothing") }
        send(.tapDisabledBySystem(.click, .timeout))
        XCTAssertEqual(send(.trustProbe(.trusted, generation: inFlight)), [])
        let effects = pressShift()
        XCTAssertNotNil(generation(in: effects))
        XCTAssertFalse(effects.contains(.enableClickTap))
    }

    func testAnAnswerAskedWhileAwayVouchesForNothingOnceBack() {
        startWatching()
        send(.suspend)
        guard let inFlight = generation(in: send(.tapDisabledBySystem(.sentinel, .timeout)))
        else { return XCTFail("nothing was asked") }
        send(.resume(trusted: true))
        send(.trustProbe(.trusted, generation: inFlight))
        let effects = pressShift()
        XCTAssertNotNil(generation(in: effects))
        XCTAssertFalse(effects.contains(.enableClickTap))
    }

    // MARK: - Creating the taps

    /// A process that has just started reads the grant as it is. One that has been running may be reading an
    /// answer from before the grant was taken away, so after a loss nothing is created on that answer alone.
    func testAfterALossStartingAsksBeforeItCreatesAnything() {
        startWatching()
        send(.trustLost)
        let effects = send(.start(trusted: true))
        XCTAssertFalse(effects.contains(.createTaps))
        XCTAssertEqual(answer(effects, .trusted), [.createTaps])
    }

    func testAfterALossARefusedAnswerCreatesNothing() {
        startWatching()
        send(.trustLost)
        XCTAssertEqual(answer(send(.start(trusted: true)), .revoked), [])
        XCTAssertEqual(life.phase, .off(.needsPermission))
    }

    func testAfterALossAnAnswerThatNeverCameCreatesNothing() {
        startWatching()
        send(.trustLost)
        XCTAssertEqual(answer(send(.start(trusted: true)), .unknown), [])
        XCTAssertEqual(life.phase, .off(.needsPermission))
    }

    /// The wizard's poll asks every two seconds. A tap macOS goes on refusing is said once.
    func testATapMacOSGoesOnRefusingIsLoggedOnce() {
        func refusalsLogged(_ effects: [Effect]) -> Int {
            effects.filter { if case .log(.error, _) = $0 { return true } else { return false } }.count
        }
        send(.start(trusted: true))
        XCTAssertEqual(refusalsLogged(life.handle(.tapsCreated(false), now: now)), 1)
        let asked = send(.start(trusted: true))
        XCTAssertEqual(answer(asked, .trusted), [.createTaps])
        XCTAssertEqual(refusalsLogged(life.handle(.tapsCreated(false), now: now)), 0)
        XCTAssertEqual(life.phase, .off(.refused))
    }

    /// Losing the grant and getting it back is not somebody asking for another try.
    func testCreatingTheTapsAgainDoesNotStartTheTripCountOver() {
        arm()
        send(.tapDisabledBySystem(.click, .timeout), after: 1)
        answer(pressShift(), .trusted)
        send(.tapDisabledBySystem(.click, .timeout), after: 1)
        send(.trustLost)
        answer(send(.start(trusted: true)), .trusted)
        send(.tapsCreated(true))
        answer(pressShift(), .trusted)
        XCTAssertEqual(life.phase, .armed)
        send(.tapDisabledBySystem(.click, .timeout), after: 1)
        XCTAssertEqual(life.phase, .off(.breakerOpen))
    }

    /// A start that was waiting for its answer is over once the taps exist, however they came to: a refusal
    /// heard later, with the breaker open, is not the answer to it, and does not close the breaker on the way.
    func testAStartOvertakenByALookAgainLeavesNothingWaiting() {
        send(.start(trusted: false))
        guard let waiting = generation(in: send(.start(trusted: true))) else { return XCTFail("nothing was asked") }
        XCTAssertEqual(send(.trustRecheck(.trusted)), [.createTaps])
        send(.tapsCreated(true))
        answer(pressShift(), .trusted)
        for _ in 0..<K.breakerTrips { send(.tapDisabledBySystem(.click, .timeout), after: 1) }
        XCTAssertEqual(life.phase, .off(.breakerOpen))
        send(.trustProbe(.revoked, generation: waiting))
        XCTAssertEqual(life.phase, .off(.breakerOpen))
    }

    /// macOS refused the taps with the grant reading as given; a live look finds it gone. What the user is
    /// told is the thing to fix.
    func testALookAgainThatFindsNoGrantAfterARefusalSaysSo() {
        send(.start(trusted: true))
        send(.tapsCreated(false))
        XCTAssertEqual(send(.trustRecheck(.revoked)), [.report(.needsPermission)])
        XCTAssertEqual(life.phase, .off(.needsPermission))
    }

    // MARK: - Away is remembered

    func testTapsCreatedWhileTheMacIsAwayArmNothing() {
        send(.start(trusted: false))
        XCTAssertEqual(send(.suspend), [])
        answer(send(.start(trusted: true)), .trusted)
        send(.tapsCreated(true))
        XCTAssertEqual(life.phase, .suspended)
        XCTAssertEqual(pressShift(), [])
        XCTAssertEqual(send(.resume(trusted: true)), [.enableSentinel])
        XCTAssertEqual(life.phase, .idle)
    }

    /// The listener holds nothing up, so a Dock that answers nobody does not keep it off for good.
    func testTheSentinelComesBackEvenWhenNobodyAnswers() {
        startWatching()
        let asked = send(.tapDisabledBySystem(.sentinel, .timeout))
        XCTAssertEqual(answer(asked, .unknown), [])
        XCTAssertEqual(send(.trustRecheck(.unknown)), [.enableSentinel])
        XCTAssertEqual(send(.trustRecheck(.unknown)), [])
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
