import XCTest
import ShiftPickCore

/// Why nobody can be clicking, and what that does to the click listener. The listener is suspended for
/// exactly as long as a reason is held, whichever reason ends last and in whichever order the notifications
/// come: a lid closed for a minute once left it suspended for good, with every window saying it was
/// listening, because the reason that ended last was looked at only once it was gone (`docs/pitfalls.md` 17).
final class AwayReasonsTests: XCTestCase {
    private typealias Effect = AwayReasons.Effect

    private var away = AwayReasons()

    /// The session as it reads once somebody has unlocked the Mac.
    private static let awakeAndUnlocked = AwayReasons.Session(screenIsLocked: false, onConsole: true)
    /// The session as it reads when the Mac has woken to its lock screen.
    private static let stillLocked = AwayReasons.Session(screenIsLocked: true, onConsole: true)
    /// The session as it reads while another user's session is in front.
    private static let someoneElses = AwayReasons.Session(screenIsLocked: false, onConsole: false)

    /// What the event made the app do, without the log lines.
    private func acts(_ effects: [Effect]) -> [Effect] {
        effects.filter {
            if case .log = $0 { return false }
            return true
        }
    }

    private func lines(_ effects: [Effect]) -> [String] {
        effects.compactMap {
            if case .log(let line) = $0 { return line }
            return nil
        }
    }

    // MARK: - The lid: it both sleeps and locks

    func testTheFirstReasonSuspendsAndTheSecondOnlySaysSo() {
        let sleep = away.went(away: .asleep)
        XCTAssertEqual(acts(sleep), [.suspend])
        XCTAssertEqual(lines(sleep), ["away (asleep); nothing arms until it is over"])
        let lock = away.went(away: .locked)
        XCTAssertEqual(acts(lock), [])
        XCTAssertEqual(lines(lock), ["away (locked); nothing arms until it is over"])
        XCTAssertTrue(away.isSuspended)
        XCTAssertEqual(away.held, [.asleep, .locked])
    }

    /// The order measured with the lid opened and the Mac unlocked at once: the unlock notice arrives before
    /// any wake notice, and one reconcile clears both.
    func testTheUnlockFirstClearsBothAndResumes() {
        away.went(away: .asleep)
        away.went(away: .locked)
        let back = away.came(backFrom: .locked, session: Self.awakeAndUnlocked)
        XCTAssertEqual(acts(back), [.resume])
        XCTAssertEqual(lines(back), ["back (locked); nothing is away any more"])
        XCTAssertFalse(away.isSuspended)
        XCTAssertTrue(away.held.isEmpty)
        // The wake notice that follows has nothing left to end.
        XCTAssertEqual(away.came(backFrom: .asleep, session: Self.awakeAndUnlocked), [])
    }

    /// The order measured with the Mac woken to its lock screen and unlocked by Touch ID three seconds
    /// later: the wake notice first, then the unlock. **The reason that ends last resumes the listener.**
    func testTheWakeFirstThenTheUnlockResumes() {
        away.went(away: .asleep)
        away.went(away: .locked)
        let wake = away.came(backFrom: .asleep, session: Self.stillLocked)
        XCTAssertEqual(acts(wake), [])
        XCTAssertEqual(lines(wake), ["back (asleep); still away: locked"])
        XCTAssertTrue(away.isSuspended)
        let unlock = away.came(backFrom: .locked, session: Self.awakeAndUnlocked)
        XCTAssertEqual(acts(unlock), [.resume])
        XCTAssertEqual(lines(unlock), ["back (locked); nothing is away any more"])
        XCTAssertFalse(away.isSuspended)
        XCTAssertTrue(away.held.isEmpty)
    }

    func testTheWakeWhileStillLockedKeepsTheListenerSuspended() {
        away.went(away: .asleep)
        away.went(away: .locked)
        away.came(backFrom: .asleep, session: Self.stillLocked)
        XCTAssertTrue(away.isSuspended)
        XCTAssertEqual(away.held, [.locked])
    }

    func testAReasonHeardTwiceIsHeardOnce() {
        away.went(away: .locked)
        XCTAssertEqual(away.went(away: .locked), [])
        XCTAssertEqual(away.held, [.locked])
    }

    func testAReasonNeverHeardGoingIsNothingToComeBackFrom() {
        XCTAssertEqual(away.came(backFrom: .asleep, session: Self.awakeAndUnlocked), [])
        XCTAssertFalse(away.isSuspended)
        XCTAssertTrue(away.held.isEmpty)
    }

    /// The sleep notice was lost and the wake notice was not: a wake is news that the Mac is awake and, with
    /// the session unlocked, that the lock is over too.
    func testAWakeNeverHeardGoingStillEndsTheLockWhenTheSessionSaysSo() {
        away.went(away: .locked)
        let wake = away.came(backFrom: .asleep, session: Self.awakeAndUnlocked)
        XCTAssertEqual(acts(wake), [.resume])
        XCTAssertEqual(lines(wake), ["back (asleep); nothing is away any more"])
        XCTAssertFalse(away.isSuspended)
    }

    /// The unlock notice was lost: the wake notice alone, with the screen still locked, leaves the lock
    /// held, and the next news ends it.
    func testALostUnlockIsEndedByTheNextNews() {
        away.went(away: .asleep)
        away.went(away: .locked)
        away.came(backFrom: .asleep, session: Self.stillLocked)
        let press = away.shiftPressed(session: Self.awakeAndUnlocked)
        XCTAssertEqual(acts(press), [.resume])
        XCTAssertEqual(lines(press), ["⇧ Shift was pressed; nothing is away any more"])
        XCTAssertFalse(away.isSuspended)
    }

    // MARK: - ⇧ Shift heard while the listener is suspended

    func testShiftPressedOnTheLockScreenKeepsTheListenerSuspended() {
        away.went(away: .locked)
        let press = away.shiftPressed(session: Self.stillLocked)
        XCTAssertEqual(acts(press), [])
        XCTAssertEqual(lines(press), ["⇧ Shift was pressed; still away: locked"])
        XCTAssertTrue(away.isSuspended)
    }

    /// The listener asks because it is suspended, and the answer comes from the session, not from what is
    /// held: with nothing held and the session clear, the listener is told to resume all the same.
    func testShiftPressedWithNothingHeldStillAnswersTheListener() {
        let press = away.shiftPressed(session: Self.awakeAndUnlocked)
        XCTAssertEqual(acts(press), [.resume])
        XCTAssertEqual(lines(press), ["⇧ Shift was pressed; nothing is away any more"])
        XCTAssertFalse(away.isSuspended)
    }

    // MARK: - Another user's session

    /// A reason's own notification of coming back ends it whatever the session reads at that instant:
    /// loginwindow writes the lock state milliseconds before it sends the unlock, and nothing promises every
    /// key before every notice. The session ends the other reasons, and never begins one.
    func testAReasonsOwnNotificationEndsItWhateverTheSessionReads() {
        away.went(away: .anotherSession)
        XCTAssertEqual(acts(away.came(backFrom: .anotherSession, session: Self.someoneElses)), [.resume])
        XCTAssertTrue(away.held.isEmpty)
        away.went(away: .locked)
        XCTAssertEqual(acts(away.came(backFrom: .locked, session: Self.stillLocked)), [.resume])
        XCTAssertTrue(away.held.isEmpty)
    }

    /// The session ends a reason whose own notification was lost, once it says so, and not before.
    func testTheSessionEndsAnotherSessionOnceTheConsoleIsOurs() {
        away.went(away: .anotherSession)
        XCTAssertEqual(acts(away.came(backFrom: .asleep, session: Self.someoneElses)), [])
        XCTAssertEqual(away.held, [.anotherSession])
        XCTAssertEqual(acts(away.came(backFrom: .asleep, session: Self.awakeAndUnlocked)), [.resume])
        XCTAssertTrue(away.held.isEmpty)
    }

    func testTheLogNamesEverythingStillAwayInOneOrder() {
        away.went(away: .anotherSession)
        away.went(away: .locked)
        away.went(away: .asleep)
        let wake = away.came(backFrom: .asleep, session: AwayReasons.Session(screenIsLocked: true, onConsole: false))
        XCTAssertEqual(lines(wake), ["back (asleep); still away: anotherSession, locked"])
        XCTAssertTrue(away.isSuspended)
    }

    // MARK: - Whatever happens

    /// SplitMix64: small, seedable, and the same on every machine.
    private struct Generator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
        mutating func flip() -> Bool { next() & 1 == 1 }
    }

    /// Thousands of notifications in an order nobody would write, with the session answering at random, and
    /// after every one of them: the listener is suspended exactly while a reason is held, it is only ever
    /// told to suspend while it listens and to resume while it is suspended, news that finds the session
    /// clear leaves nothing held, and nothing moves in silence.
    func testTheListenerIsSuspendedExactlyWhileAReasonIsHeldWhateverHappens() {
        for seed in UInt64(1)...200 {
            var random = Generator(state: seed)
            var away = AwayReasons()
            /// What the engine would have done: `.suspend` and `.resume`, applied in order.
            var engineSuspended = false
            for step in 0..<300 {
                let session = AwayReasons.Session(screenIsLocked: random.flip(), onConsole: random.below(4) > 0)
                let reason = AwayReasons.Reason.allCases[random.below(AwayReasons.Reason.allCases.count)]
                let heldBefore = away.held
                let effects: [Effect]
                let news: String
                switch random.below(5) {
                case 0, 1:
                    effects = away.went(away: reason)
                    news = "went(\(reason))"
                case 2, 3:
                    effects = away.came(backFrom: reason, session: session)
                    news = "came(\(reason), \(session))"
                default:
                    // The listener asks only while it is suspended (TapLifecycle emits checkStillAway in no
                    // other phase), so that is the only time the press is fed.
                    guard engineSuspended else { continue }
                    effects = away.shiftPressed(session: session)
                    news = "shiftPressed(\(session))"
                }
                let context = "seed \(seed), step \(step), \(heldBefore) + \(news) -> \(away.held), \(effects)"
                for effect in effects {
                    switch effect {
                    case .suspend:
                        XCTAssertFalse(engineSuspended, "suspended twice: \(context)")
                        engineSuspended = true
                    case .resume:
                        XCTAssertTrue(engineSuspended, "resumed while listening: \(context)")
                        engineSuspended = false
                    case .log:
                        break
                    }
                }
                XCTAssertEqual(away.isSuspended, engineSuspended, context)
                XCTAssertEqual(engineSuspended, !away.held.isEmpty, context)
                // A reason's own notification of coming back ends it, whatever the session reads.
                if news.hasPrefix("came") { XCTAssertFalse(away.held.contains(reason), context) }
                let sessionIsClear = !session.screenIsLocked && session.onConsole
                if sessionIsClear, !news.hasPrefix("went"), !heldBefore.isEmpty {
                    XCTAssertTrue(away.held.isEmpty, "news with the session clear left something held: \(context)")
                }
                let moved = heldBefore != away.held || effects.contains(.suspend) || effects.contains(.resume)
                if moved { XCTAssertFalse(lines(effects).isEmpty, "moved in silence: \(context)") }
            }
        }
    }
}
