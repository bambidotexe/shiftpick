import XCTest
import ShiftPickCore

/// The rules of `TapLifecycleTests` are the scenarios somebody thought of. This is for the ones nobody did:
/// thousands of events in an order no person would write, and after every one of them the same few
/// sentences have to hold.
///
/// The sequences are drawn from a seeded generator, so a failure names a seed and a step that fail again the
/// next time they are run.
final class TapLifecycleInvariantTests: XCTestCase {
    /// What the executor would have done, reduced to the two facts that matter: do the taps exist, and is
    /// the click tap enabled.
    private struct World {
        var tapsExist = false
        var clickTapEnabled = false
        var watchdogRuns = false

        mutating func apply(_ effects: [TapLifecycle.Effect], seed: UInt64, step: Int) {
            for effect in effects {
                switch effect {
                case .createTaps:
                    XCTAssertFalse(tapsExist, "taps created twice (seed \(seed), step \(step))")
                case .destroyTaps:
                    tapsExist = false
                    clickTapEnabled = false
                case .enableClickTap:
                    XCTAssertTrue(tapsExist, "a tap that does not exist was enabled (seed \(seed), step \(step))")
                    clickTapEnabled = true
                case .disableClickTap:
                    clickTapEnabled = false
                case .startWatchdog:
                    watchdogRuns = true
                case .stopWatchdog:
                    watchdogRuns = false
                case .enableSentinel, .probeTrust, .recheckTrustSoon, .report, .log:
                    break
                }
            }
        }
    }

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

    func testTheClickTapIsOnlyEverEnabledWhileArmedWhateverHappens() {
        for seed in UInt64(1)...200 {
            run(seed: seed, steps: 400)
        }
    }

    private func run(seed: UInt64, steps: Int) {
        var random = Generator(state: seed)
        var life = TapLifecycle(userEnabled: true)
        var world = World()
        var now: TimeInterval = 0
        var lastGeneration = 0
        var lastStatus = life.status
        /// What the modifier keys last said: ⇧ Shift down with neither ⌥ Option nor ⌃ Control.
        var keysAskForIt = false

        for step in 0..<steps {
            now += [0, 0.01, 0.4, 3, 70][random.below(5)]
            let event = self.event(&random, lastGeneration: lastGeneration)
            let before = life.phase
            var effects = life.handle(event, now: now)
            for case .probeTrust(let generation) in effects { lastGeneration = generation }

            // The executor answers `createTaps` at once, as the real one does, so what that answer causes
            // belongs to the same step.
            world.apply(effects, seed: seed, step: step)
            if effects.contains(.createTaps) {
                let created = random.below(10) > 0
                world.tapsExist = created
                let answer = life.handle(.tapsCreated(created), now: now)
                world.apply(answer, seed: seed, step: step)
                effects += answer
            }

            let context = "seed \(seed), step \(step), \(before) + \(event) -> \(life.phase)"

            // 1. The click tap is enabled in exactly one phase.
            XCTAssertEqual(world.clickTapEnabled, life.phase == .armed, context)
            // 2. The watch is kept in exactly that phase too: no timer is left running while idle.
            XCTAssertEqual(world.watchdogRuns, life.phase == .armed, context)
            // 3. No tap of either kind exists while the lifecycle says it is off.
            if case .off = life.phase { XCTAssertFalse(world.tapsExist, context) }
            // 4. The transition that reports a tap macOS disabled never enables one.
            if case .tapDisabledBySystem = event { XCTAssertFalse(effects.contains(.enableClickTap), context) }
            // 5. Arming needs the user's switch, ⇧ Shift, and a trusted answer or a fresh one: it never
            //    comes out of any other event.
            if effects.contains(.enableClickTap) {
                switch event {
                case .trustProbe(.trusted, _), .modifiers(shift: true, optionOrControl: false): break
                default: XCTFail("armed by \(event): \(context)")
                }
            }
            // 8. The click tap is never enabled unless the modifier keys last said so: ⇧ Shift down, and
            //    neither ⌥ Option nor ⌃ Control. A swallowed press keeps it enabled; nothing enables it again.
            if case .modifiers(let shift, let optionOrControl) = event { keysAskForIt = shift && !optionOrControl }
            if case .watchdog(false, _) = event { keysAskForIt = false }
            if effects.contains(.enableClickTap) { XCTAssertTrue(keysAskForIt, context) }
            // 9. Taps are created on a live answer, or by a process that has only just started and reads the
            //    grant as it is. Never on the cached answer of one that has been running.
            if effects.contains(.createTaps) {
                switch (event, before) {
                case (.trustProbe(.trusted, _), _), (.trustRecheck(.trusted), _): break
                case (.start(trusted: true), .off(.notStarted)): break
                default: XCTFail("taps created by \(event): \(context)")
                }
            }
            // 6. Every change of status is reported, and nothing else is.
            let reported = effects.compactMap { effect -> TapLifecycle.Status? in
                if case .report(let status) = effect { return status }
                return nil
            }
            if life.status != lastStatus {
                XCTAssertEqual(reported.last, life.status, context)
            } else {
                XCTAssertTrue(reported.isEmpty, context)
            }
            lastStatus = life.status
            // 7. Terminated is for good.
            if before == .off(.terminated) {
                XCTAssertEqual(life.phase, .off(.terminated), context)
                XCTAssertTrue(effects.isEmpty, context)
            }
        }
    }

    private func event(_ random: inout Generator, lastGeneration: Int) -> TapLifecycle.Event {
        switch random.below(24) {
        case 0: return random.below(3) == 0 ? .tryAgain(trusted: random.below(4) > 0)
                                            : .start(trusted: random.below(4) > 0)
        case 1, 2, 3: return .modifiers(shift: true, optionOrControl: random.below(6) == 0)
        case 4, 5: return .modifiers(shift: false, optionOrControl: false)
        case 6, 7, 8:
            // Mostly the answer to the question that was asked; sometimes to one asked long ago.
            let generation = random.below(4) > 0 ? lastGeneration : lastGeneration - 1
            return .trustProbe([.trusted, .trusted, .trusted, .unknown, .revoked][random.below(5)],
                               generation: generation)
        case 9: return .trustRecheck([.trusted, .trusted, .unknown, .revoked][random.below(4)])
        case 10: return .trustNotification
        case 11: return random.below(6) == 0 ? .trustLost : .trustNotification
        case 12, 13: return .pressDecided(number: Int64(random.below(3)), swallowed: random.flip())
        case 14, 15: return .releaseSeen(number: Int64(random.below(3)))
        case 16: return .tapDisabledBySystem(random.flip() ? .click : .sentinel,
                                             [.timeout, .userInput, .wouldNotEnable][random.below(3)])
        case 17, 18: return .watchdog(shiftDown: random.flip(), buttonDown: random.flip())
        case 19: return .suspend
        case 20: return .resume(trusted: random.below(5) > 0)
        case 21: return .userEnabled(random.below(3) > 0)
        case 22: return random.below(40) == 0 ? .terminate : .suspend
        default: return .resume(trusted: true)
        }
    }
}
