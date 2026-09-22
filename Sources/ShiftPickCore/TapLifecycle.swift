import Foundation

/// When the click tap may be enabled, and what every event does to it.
///
/// ShiftPick holds two event taps. The **sentinel** only listens: it hears ⇧ Shift go down and come up, and
/// a listening tap cannot hold an event up whatever happens to the process behind it. The **click tap** can
/// swallow a click, which is the whole feature, and is therefore the one object in the app that can hold up
/// the Mac's input: an enabled tap of that kind whose owner has lost the Accessibility grant stalls every
/// click in the session (`docs/pitfalls.md`). Everything here exists so that the click tap is enabled for as
/// little of the process's life as the gesture needs, and never by reflex:
///
/// - **It is enabled only while ⇧ Shift is held**, or while a press it swallowed is still waiting for its
///   release. With no finger on the key there is no enabled click tap for a revoked grant, a hung thread or a
///   sleeping Mac to go wrong with.
/// - **Arming asks first.** A live answer about the grant, no older than `K.trustFreshness` and asked after
///   the grant was last put in doubt, or nothing is enabled. **So does creating the taps**, except in a
///   process that has only just started, which reads the grant as it is.
/// - **A tap macOS disabled is never enabled again by the event that says so.** macOS disables a tap that
///   stopped answering; that is the system's own safety net, and enabling the tap again from the callback
///   cuts a hole in it. The next ⇧ Shift press arms again, through the same question as any other, and
///   `K.breakerTrips` timeouts inside `K.breakerWindow` end it for good. **A tap disabled "for user input"
///   is not counted**: that is also what macOS says back to a tap the app disables itself.
/// - **Anything that says the grant is gone destroys both taps**, and anything that says it *may* have moved
///   disarms first and asks afterwards.
/// - **A watch is kept while armed, and it disarms rather than wait**: on the keys no longer asking for it,
///   on a minute with nothing clicked, and on a question about the grant still unanswered at the next look.
///
/// It is a value: an event and the time go in, the new state and what to do about it come out. The taps, the
/// threads and the clock are `ShiftPickPlatform.ClickGuard`'s, which does what the effects say and nothing
/// else, in the order they are given.
public struct TapLifecycle: Equatable, Sendable {
    /// Why no tap exists.
    public enum OffReason: Equatable, Sendable {
        case notStarted
        /// The Accessibility grant is missing, or was taken away.
        case needsPermission
        /// The grant reads as given and macOS would still not create the taps.
        case refused
        /// macOS kept taking the click tap away, so ShiftPick stopped creating it.
        case breakerOpen
        /// Quit, uninstall, or an update about to replace the bundle. Nothing comes after it.
        case terminated
    }

    public enum Phase: Equatable, Sendable {
        case off(OffReason)
        /// Both taps exist; the sentinel listens and the click tap is disabled.
        case idle
        /// ⇧ Shift is down and the live question about the grant has not been answered yet.
        case arming
        /// The click tap is enabled.
        case armed
        /// Both taps exist and nothing arms: the Mac is asleep, locked, or showing another user's session.
        case suspended
    }

    public enum Tap: Equatable, Sendable { case sentinel, click }

    /// Why macOS says a tap stopped. **A timeout** is a callback the window server gave up waiting for, which
    /// is what a revoked grant under an enabled tap looks like, and it is counted. **User input** is what
    /// macOS also sends back to a tap the app disables itself, at creation and at every disarm, so it is not.
    public enum DisableReason: String, Equatable, Sendable { case timeout, userInput }

    public enum LogLevel: Equatable, Sendable { case debug, notice, error }

    public enum Event: Equatable, Sendable {
        /// Launch, the grant arriving, a poll that finds the grant in place. `trusted` is the cached answer,
        /// which only a process that has just started may create taps on: after that it asks a live question
        /// first. Does nothing while the taps exist, **and nothing while the breaker is open**: none of those
        /// is somebody asking for another try.
        case start(trusted: Bool)
        /// The user asking for another try after the breaker opened, and the only thing that closes it.
        case tryAgain(trusted: Bool)
        /// The answer to `createTaps`.
        case tapsCreated(Bool)
        /// The modifier keys as the sentinel, or a click's own flags, last saw them.
        case modifiers(shift: Bool, optionOrControl: Bool)
        /// The answer to `probeTrust`, carrying the generation that question was asked with.
        case trustProbe(TrustVerdict, generation: Int)
        /// One of the looks `recheckTrustSoon` asks for.
        case trustRecheck(TrustVerdict)
        /// The system said the privacy database moved. It may not be about this app at all.
        case trustNotification
        /// An Accessibility call came back `apiDisabled`, or `AXIsProcessTrusted()` answered false.
        case trustLost
        /// The click tap saw a press and decided it.
        case pressDecided(number: Int64, swallowed: Bool)
        case releaseSeen(number: Int64)
        case tapDisabledBySystem(Tap, DisableReason)
        /// The look kept while armed, with what the keyboard and the mouse say themselves. The grant is not in
        /// it: the live question this asks carries that, from a thread nobody's click is waiting on.
        case watchdog(shiftDown: Bool, optionOrControlDown: Bool, buttonDown: Bool)
        case suspend
        case resume(trusted: Bool)
        case terminate
    }

    public enum Effect: Equatable, Sendable {
        /// Both taps, the sentinel enabled and the click tap **disabled**. Answered with `tapsCreated`.
        case createTaps
        case destroyTaps
        case enableClickTap
        case disableClickTap
        case enableSentinel
        /// Ask another process a real Accessibility question. Answered with `trustProbe` and this number.
        case probeTrust(Int)
        /// Look at the grant again at each of `K.trustRecheckDelays`. Answered with `trustRecheck`.
        case recheckTrustSoon
        case startWatchdog
        case stopWatchdog
        /// Somebody pressed ⇧ Shift while the Mac is said to be away. Look at the session itself, and resume
        /// if nothing is away any more: a notification that would have said so may have been lost.
        case checkStillAway
        case report(Status)
        case log(LogLevel, String)
    }

    /// What the windows and the menu are told. Arming is not in it: that happens at every capital letter,
    /// and none of it is news.
    public enum Status: Equatable, Sendable {
        case stopped, needsPermission, refused, breakerOpen, watching
    }

    public private(set) var phase: Phase = .off(.notStarted)

    /// ⇧ Shift is down with neither ⌥ Option nor ⌃ Control: the one state of the modifier keys in which the
    /// click tap has any business being enabled.
    private var keysAskForIt = false
    /// The Mac is asleep, locked, or showing another user's session. Remembered whatever the phase is, so
    /// that taps created meanwhile arm nothing either.
    private var isAway = false
    /// A `start` is waiting for a live answer before it creates anything.
    private var startIsWaiting = false
    /// The watch's last question about the grant has not been answered yet.
    private var watchIsWaiting = false
    /// When ⇧ Shift heard while away last made the session be looked at again.
    private var lastAwayCheck: TimeInterval?
    /// The event number of a press that was swallowed and whose release has not come. macOS gives a press
    /// and its release the same number, which is what makes the release recognisable.
    private var outstandingPress: Int64?
    /// When the tap was armed or last saw a click, whichever is later: what the idle limit counts from.
    private var lastActivity: TimeInterval = 0
    private var trustVerifiedAt: TimeInterval?
    /// Bumped whenever an answer still on its way has to be ignored.
    private var probeGeneration = 0
    private var sentinelIsDown = false
    /// When macOS took a tap away, inside `K.breakerWindow`.
    private var trips: [TimeInterval] = []

    public init() {}

    public var status: Status {
        switch phase {
        case .off(.notStarted), .off(.terminated): .stopped
        case .off(.needsPermission): .needsPermission
        case .off(.refused): .refused
        case .off(.breakerOpen): .breakerOpen
        case .idle, .arming, .armed, .suspended: .watching
        }
    }

    /// Whether this release belongs to a press that was swallowed. Finder never saw that press, and would
    /// apply its own ⇧ Shift toggle to the clicked file if it were handed the release.
    public func shouldSwallowRelease(_ number: Int64) -> Bool {
        outstandingPress == number
    }

    public mutating func handle(_ event: Event, now: TimeInterval) -> [Effect] {
        // Nothing comes after the end: no event can create a tap in a process that is on its way out.
        guard phase != .off(.terminated) else { return [] }
        let before = status
        var effects = transition(event, now: now)
        if status != before { effects.append(.report(status)) }
        return effects
    }

    // MARK: - Transitions

    private var tapsExist: Bool {
        if case .off = phase { return false }
        return true
    }

    private mutating func transition(_ event: Event, now: TimeInterval) -> [Effect] {
        switch event {
        case .start(let trusted):
            // An open breaker is not something a launch, a grant or a poll gets to close: `tryAgain` does.
            guard case .off(let reason) = phase, reason != .breakerOpen else { return [] }
            return begin(trusted: trusted, justLaunched: reason == .notStarted)

        case .tryAgain(let trusted):
            guard phase == .off(.breakerOpen) else { return [] }
            trips = []
            return begin(trusted: trusted, justLaunched: false) + [.log(.notice, "another try was asked for")]

        case .tapsCreated(let created):
            guard case .off = phase else { return [] }
            // Whichever answer led here, no start is waiting for one any more.
            startIsWaiting = false
            guard created else {
                // Said once. Whoever keeps asking, the wizard's poll for one, hears nothing new.
                let alreadySaid = phase == .off(.refused)
                phase = .off(.refused)
                return alreadySaid ? [] : [.log(.error, "macOS would not create the event taps although the grant is in place")]
            }
            // The trips are not forgotten: losing the grant and getting it back is not somebody asking for
            // another try. They lapse on their own after `K.breakerWindow`.
            phase = isAway ? .suspended : .idle
            lastAwayCheck = nil
            forgetTrust()
            sentinelIsDown = false
            outstandingPress = nil
            return [.log(.notice, "listening for ⇧ Shift; the click tap exists and is disabled")]

        case .modifiers(let shift, let optionOrControl):
            keysAskForIt = shift && !optionOrControl
            switch phase {
            case .idle where keysAskForIt && !sentinelIsDown:
                if let verified = trustVerifiedAt, (0...K.trustFreshness).contains(now - verified) {
                    return arm(now: now)
                }
                phase = .arming
                return [askAboutTheGrant()]
            case .arming where !keysAskForIt:
                phase = .idle
                probeGeneration += 1
                return []
            case .armed where !keysAskForIt && outstandingPress == nil:
                return disarm()
            case .suspended where keysAskForIt:
                // Somebody at the keyboard while the Mac is said to be away: a notification that would have
                // said otherwise may have been lost, so the session is looked at itself, and no more often
                // than the interval, because a password typed on the lock screen is ⇧ Shift too.
                if let asked = lastAwayCheck, now - asked < K.awayCheckInterval { return [] }
                lastAwayCheck = now
                return [.checkStillAway]
            default:
                return []
            }

        case .trustProbe(let verdict, let generation):
            switch verdict {
            case .revoked:
                return loseTheGrant("a live Accessibility request was refused")
            case .trusted:
                guard generation == probeGeneration else { return [] }
                watchIsWaiting = false
                guard tapsExist else {
                    guard startIsWaiting else { return [] }
                    startIsWaiting = false
                    return [.createTaps]
                }
                trustVerifiedAt = now
                var effects: [Effect] = []
                if sentinelIsDown {
                    sentinelIsDown = false
                    effects.append(.enableSentinel)
                }
                // The keys are asked again, not remembered: they may have moved while the answer was fetched.
                if phase == .arming { effects += keysAskForIt ? arm(now: now) : stopArming() }
                return effects
            case .unknown:
                guard generation == probeGeneration else { return [] }
                // Nobody answered, which says nothing either way: not even that the last answer still holds.
                trustVerifiedAt = nil
                watchIsWaiting = false
                if startIsWaiting {
                    startIsWaiting = false
                    return [.log(.notice, "nothing created: nobody answered the question about the grant")]
                }
                switch phase {
                case .arming:
                    phase = .idle
                    return [.log(.debug, "not armed: nobody answered the question about the grant")]
                case .armed:
                    return disarm() + [.log(.notice, "disarmed: nobody answered the question about the grant")]
                default:
                    return []
                }
            }

        case .trustRecheck(let verdict):
            switch (verdict, phase) {
            case (.revoked, _):
                return loseTheGrant("the grant read as gone when it was looked at again")
            case (.trusted, .off(.needsPermission)), (.trusted, .off(.refused)):
                return [.createTaps]
            case (.trusted, _) where tapsExist:
                return bringTheSentinelBack()
            case (.unknown, _) where tapsExist:
                // A listener holds nothing up, so nobody answering is no reason to keep it off for good.
                return bringTheSentinelBack()
            default:
                return []
            }

        case .trustNotification:
            forgetTrust()
            switch phase {
            case .armed:
                // The tap first, the question after: the other order leaves it enabled while the answer is
                // fetched. And the question only on behalf of keys that still ask for it: a tap that was only
                // still armed for the release of a swallowed press has nothing to be armed again for.
                var effects = disarm()
                if keysAskForIt {
                    phase = .arming
                    effects.append(askAboutTheGrant())
                }
                return effects + [.recheckTrustSoon]
            case .arming:
                return [askAboutTheGrant(), .recheckTrustSoon]
            case .idle, .suspended:
                return [.recheckTrustSoon]
            case .off(.needsPermission), .off(.refused), .off(.breakerOpen):
                // A start or a try still waiting for its answer is asked again: the answer on its way was
                // asked before the move, and counts for nothing now.
                var effects: [Effect] = startIsWaiting ? [askAboutTheGrant()] : []
                if phase != .off(.breakerOpen) { effects.append(.recheckTrustSoon) }
                return effects
            case .off:
                return []
            }

        case .trustLost:
            return loseTheGrant("an Accessibility call was refused")

        case .pressDecided(let number, let swallowed):
            lastActivity = now
            outstandingPress = swallowed ? number : nil
            return []

        case .releaseSeen(let number):
            guard outstandingPress == number else { return [] }
            outstandingPress = nil
            return phase == .armed && !keysAskForIt ? disarm() : []

        case .tapDisabledBySystem(let tap, let reason):
            guard tapsExist else { return [] }
            return reason == .userInput ? disabledForUserInput(tap) : tripped(tap, reason, now: now)

        case .watchdog(let shiftDown, let optionOrControlDown, let buttonDown):
            // What the keyboard says about itself is believed whatever the phase is.
            let keysStopAsking = !shiftDown || optionOrControlDown
            if keysStopAsking { keysAskForIt = false }
            guard phase == .armed else { return [.stopWatchdog] }
            if keysStopAsking && !(outstandingPress != nil && buttonDown) {
                return disarm() + [.log(.notice, "disarmed: the keys stopped asking for it and nothing said so")]
            }
            if now - lastActivity > K.armedIdleLimit {
                return disarm() + [.log(.notice, "disarmed: ⇧ Shift held with nothing clicked")]
            }
            // An answer that has not come in a whole look is a worker nobody can vouch for the grant through.
            // The tap does not stay enabled on an older answer while this one is awaited.
            if watchIsWaiting {
                return disarm() + [.log(.notice, "disarmed: the last look's question about the grant went unanswered")]
            }
            watchIsWaiting = true
            return [askAboutTheGrant()]

        case .suspend:
            isAway = true
            guard tapsExist, phase != .suspended else { return [] }
            let effects = phase == .armed ? disarm() : []
            forgetTrust()
            phase = .suspended
            lastAwayCheck = nil
            return effects

        case .resume(let trusted):
            isAway = false
            guard phase == .suspended else { return [] }
            guard trusted else { return loseTheGrant("the grant was gone when the Mac came back") }
            phase = .idle
            // A Mac that has been away is the one place a grant can have moved with nothing heard.
            forgetTrust()
            sentinelIsDown = false
            return [.enableSentinel]

        case .terminate:
            var effects = phase == .armed ? disarm() : []
            if tapsExist { effects.append(.destroyTaps) }
            phase = .off(.terminated)
            return effects
        }
    }

    // MARK: - The few moves everything above is made of

    /// From an `off` phase only. Without the grant nothing is created, and the phase says why.
    ///
    /// **`trusted` is the cached answer, and only a process that has just started may build on it.** Such a
    /// process reads the grant as it is. One that has been running may still be reading the answer from
    /// before the grant was taken away, and a tap that can swallow is born enabled: so after a loss, a
    /// refusal or an open breaker, a live answer is fetched first and `createTaps` comes out of that.
    private mutating func begin(trusted: Bool, justLaunched: Bool) -> [Effect] {
        guard trusted else {
            phase = .off(.needsPermission)
            startIsWaiting = false
            return []
        }
        guard !justLaunched else { return [.createTaps] }
        // A question already on its way is the one that answers. Every question is answered, and asking a
        // new one would make that answer worthless: a poll faster than the worker would never be heard.
        guard !startIsWaiting else { return [] }
        startIsWaiting = true
        return [askAboutTheGrant()]
    }

    /// Whatever vouched for the grant no longer does, and neither does any answer still on its way: it was
    /// asked before the doubt.
    private mutating func forgetTrust() {
        trustVerifiedAt = nil
        probeGeneration += 1
    }

    private mutating func stopArming() -> [Effect] {
        phase = .idle
        return []
    }

    private mutating func bringTheSentinelBack() -> [Effect] {
        guard sentinelIsDown else { return [] }
        sentinelIsDown = false
        return [.enableSentinel]
    }

    /// A new question, which makes every answer still on its way an answer to an older one.
    private mutating func askAboutTheGrant() -> Effect {
        probeGeneration += 1
        return .probeTrust(probeGeneration)
    }

    private mutating func arm(now: TimeInterval) -> [Effect] {
        phase = .armed
        lastActivity = now
        outstandingPress = nil
        watchIsWaiting = false
        // At `debug`, which nobody pays for unless they are streaming it: this happens at every capital letter.
        return [.enableClickTap, .startWatchdog, .log(.debug, "armed")]
    }

    /// From `armed` only. A press still waiting for its release is forgotten with it, so that release reaches
    /// Finder, which applies its own ⇧ Shift toggle to the clicked file: a selection one file short, in the
    /// rare moment a tap has to go while a button is down, and the price of never leaving it enabled.
    private mutating func disarm() -> [Effect] {
        phase = .idle
        outstandingPress = nil
        watchIsWaiting = false
        return [.disableClickTap, .stopWatchdog, .log(.debug, "disarmed")]
    }

    private mutating func loseTheGrant(_ why: String) -> [Effect] {
        guard tapsExist else {
            // Nothing to destroy. Whatever was waiting for an answer has it, and no answer still on its way
            // counts: it was asked before the grant was known to be gone.
            if startIsWaiting || phase == .off(.refused) { phase = .off(.needsPermission) }
            startIsWaiting = false
            forgetTrust()
            return []
        }
        var effects = phase == .armed ? disarm() : []
        effects.append(.destroyTaps)
        phase = .off(.needsPermission)
        startIsWaiting = false
        sentinelIsDown = false
        forgetTrust()
        effects.append(.log(.error, "the Accessibility grant is gone (\(why)); both taps destroyed"))
        return effects
    }

    /// macOS says a tap was disabled for user input. **Most of the time that is this app's own disable heard
    /// back**, and it arrives with the lifecycle already disarmed: nothing to do, and above all no second
    /// disable, which would be heard back in turn. Otherwise the tap is off all the same, so nothing stays
    /// armed on it. It is never counted, and nothing here enables anything.
    private mutating func disabledForUserInput(_ tap: Tap) -> [Effect] {
        switch tap {
        case .click:
            guard phase == .armed else { return [] }
            return disarm() + [.log(.notice, "disarmed: macOS disabled the click tap for user input")]
        case .sentinel:
            // Without the listener the release of ⇧ Shift would not be heard, so nothing stays armed on it,
            // and it is enabled again once the grant has been answered for.
            var effects = phase == .armed ? disarm() : []
            if phase == .arming { phase = .idle }
            sentinelIsDown = true
            effects += [askAboutTheGrant(), .recheckTrustSoon,
                        .log(.notice, "macOS disabled the listener for user input; it comes back once the grant is answered for")]
            return effects
        }
    }

    /// macOS gave up waiting for a tap. **Nothing here enables one**: what comes back is the next ⇧ Shift
    /// press, asked about like any other, and after `K.breakerTrips` of these not even that.
    private mutating func tripped(_ tap: Tap, _ reason: DisableReason, now: TimeInterval) -> [Effect] {
        trips = trips.filter { (0..<K.breakerWindow).contains(now - $0) } + [now]
        // A tap that stopped answering is what a revoked grant looks like from the inside.
        forgetTrust()
        var effects: [Effect] = []
        if phase == .armed { effects += disarm() } else if tap == .click { effects.append(.disableClickTap) }
        if phase == .arming { phase = .idle }
        let count = trips.count

        guard count < K.breakerTrips else {
            effects.append(.destroyTaps)
            phase = .off(.breakerOpen)
            probeGeneration += 1
            effects.append(.log(.error, """
                macOS took the \(tap) tap away (\(reason.rawValue)) \(count) times in \
                \(Int(K.breakerWindow)) s; both taps destroyed and nothing is created again until it is asked for
                """))
            return effects
        }
        effects.append(.log(.error, """
            macOS took the \(tap) tap away (\(reason.rawValue)), \(count) of \(K.breakerTrips) inside \
            \(Int(K.breakerWindow)) s; it stays disabled until the next ⇧ Shift press is answered for
            """))
        if tap == .sentinel {
            sentinelIsDown = true
            effects.append(askAboutTheGrant())
        }
        effects.append(.recheckTrustSoon)
        return effects
    }
}

extension TapLifecycle.Status {
    /// Whether a window may show the Accessibility grant as in place. `systemSays` is `AXIsProcessTrusted()`,
    /// an answer the system keeps for the process and that was measured saying yes for seconds after the
    /// grant had gone. **Once ShiftPick has found the grant gone itself, that is what is shown**, whatever the
    /// cached answer still claims; otherwise the cached answer is, and the rows that report the taps say what
    /// else is wrong.
    public func showsGrant(systemSays: Bool) -> Bool {
        systemSays && self != .needsPermission
    }
}
