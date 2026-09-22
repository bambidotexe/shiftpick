import CoreGraphics
import Foundation
import os
import ShiftPickCore

/// The two event taps, and the only thing in the app that may swallow a click.
///
/// **What this is built against.** An event tap created with `.defaultTap` sits in the path of every click
/// in the session, and the window server waits for its answer. If its owner loses the Accessibility grant
/// while it is enabled, the callback is no longer run and the clicks are still routed into it: every one of
/// them stalls the whole session's input until the system gives up on the tap and disables it. An app that
/// enables the tap again from that callback cuts a hole in the only safety net there is, and the Mac stays
/// unusable until it is powered off (`docs/pitfalls.md` has the log of the day it happened here).
///
/// So there are two taps, and they are not alike:
///
/// - **The sentinel** is `.listenOnly`: ⇧ Shift going down and up, and plain presses for the anchor. The
///   window server does not wait for a listener, so nothing that happens to this process can make it hold
///   anything up. It is on for as long as the app is watching.
/// - **The click tap** is `.defaultTap`: left button down and up. It is **created disabled and enabled only
///   while ⇧ Shift is held**, or while a press it swallowed is waiting for its release. With no finger on
///   the key, no enabled tap of the dangerous kind exists for a revoked grant, a hung thread or a sleeping
///   Mac to go wrong with.
///
/// **This class decides nothing about when a tap is enabled.** `ShiftPickCore.TapLifecycle` decides, from
/// values alone, and hands back effects; this does what they say, in the order they are given, and reports
/// what the system did. What it carries itself is what only it can see: which press is ShiftPick's to decide
/// (`clickHeard`), that a tap the system disabled is reported and **never enabled there**, that a tap which
/// would not enable is one more trip, and that nothing is created once `shutDown` has been called.
///
/// Both taps are served by `TapThread`, which does nothing else, and every tap, timer and lifecycle change
/// happens on it. **No Accessibility call is ever made on that thread**: the question a click asks goes to
/// the worker through `Hooks.decidePress`, which comes back within `K.clickBudget + K.commitGrace` whatever
/// the worker is doing.
public final class ClickGuard: @unchecked Sendable {
    public struct Hooks {
        /// A ⇧ Shift press while armed, with the event still held: true swallows it. Called on the tap's
        /// thread, which waits for the answer, so it must come back within `K.clickBudget + K.commitGrace`.
        public var decidePress: (CGPoint, CGEventFlags) -> Bool
        /// A press without ⇧ Shift, already on its way to whoever it was for. Returns at once.
        public var plainClick: (CGPoint) -> Void
        /// Ask another process a real Accessibility question, off the tap's thread, and answer from any.
        public var probeTrust: (@escaping (TrustVerdict) -> Void) -> Void
        /// Called on the tap's thread.
        public var statusChanged: (TapLifecycle.Status) -> Void
        /// ⇧ Shift was pressed while the Mac is said to be away. Called on the tap's thread; the session is
        /// looked at elsewhere, and `resume` is the answer when nothing is away any more.
        public var checkStillAway: () -> Void

        public init(decidePress: @escaping (CGPoint, CGEventFlags) -> Bool,
                    plainClick: @escaping (CGPoint) -> Void,
                    probeTrust: @escaping (@escaping (TrustVerdict) -> Void) -> Void,
                    statusChanged: @escaping (TapLifecycle.Status) -> Void,
                    checkStillAway: @escaping () -> Void) {
            self.decidePress = decidePress
            self.plainClick = plainClick
            self.probeTrust = probeTrust
            self.statusChanged = statusChanged
            self.checkStillAway = checkStillAway
        }
    }

    private struct Ports {
        var sentinel: CFMachPort?
        var click: CFMachPort?
    }

    private let hooks: Hooks
    private let thread = TapThread(name: "\(AppIdentity.bundleIdentifier).taps")

    // Everything below belongs to the tap's thread and is touched nowhere else.
    private var lifecycle: TapLifecycle
    private var sentinel: CFMachPort?
    private var click: CFMachPort?
    private var sources: [CFRunLoopSource] = []
    private var watchdog: CFRunLoopTimer?
    private var rechecks: [CFRunLoopTimer] = []

    /// The same two ports, where a teardown that cannot wait for the tap's thread can reach them.
    private let ports = OSAllocatedUnfairLock(uncheckedState: Ports())
    /// Set by `shutDown`, from whichever thread it ran on, and never cleared: no tap is created after it,
    /// whatever the lifecycle believes. It is what holds when the taps' thread was too stuck to be told.
    private let isShutDown = OSAllocatedUnfairLock(initialState: false)
    /// Held while the click tap is enabled and for no longer. An accessory app with no window on screen is
    /// one macOS is free to nap, and a napped process has its timers put off: the watch below is a timer, and
    /// the one state it exists for is the one in which the Mac's clicks are waiting on this process.
    private var armedActivity: NSObjectProtocol?

    public init(hooks: Hooks) {
        self.hooks = hooks
        lifecycle = TapLifecycle()
    }

    /// The callbacks recover `self` from an unretained pointer, so a tap left behind would call into freed
    /// memory. The app keeps its guard for the life of the process; this is for everything else.
    deinit {
        destroyFromAnyThread()
        thread.stop()
    }

    // MARK: - What the app asks for, from any thread

    /// Launch, the grant arriving, a poll that finds the grant in place. Nothing happens when the taps
    /// already exist, and nothing while the breaker is open.
    public func start() {
        let trusted = Permissions.accessibilityGranted
        thread.perform { [weak self] in self?.feed(.start(trusted: trusted)) }
    }

    /// The user asking for another try after macOS took the click tap away too often. The only thing that
    /// closes the breaker, and nothing at all when it is not open.
    public func tryAgain() {
        let trusted = Permissions.accessibilityGranted
        thread.perform { [weak self] in self?.feed(.tryAgain(trusted: trusted)) }
    }

    /// The Mac is going to sleep, the screen is locking, or another user's session is coming forward.
    public func suspend() {
        thread.perform { [weak self] in self?.feed(.suspend) }
    }

    public func resume() {
        let trusted = Permissions.accessibilityGranted
        thread.perform { [weak self] in self?.feed(.resume(trusted: trusted)) }
    }

    /// The system said the privacy database moved. Disarms first and asks afterwards.
    public func trustMayHaveChanged() {
        thread.perform { [weak self] in self?.feed(.trustNotification) }
    }

    /// An Accessibility call was refused, or the cached answer reads as gone.
    public func trustWasLost() {
        thread.perform { [weak self] in self?.feed(.trustLost) }
    }

    /// **Returns once no tap exists**, and is what runs before anything that takes the grant, the bundle or
    /// the process away: an uninstall, an update, a quit. It asks the tap's thread and waits
    /// `K.shutDownWait`; a thread that does not answer by then is not coming back, so the ports are disabled
    /// and invalidated from here instead, which the window server honours from any thread. A block the
    /// thread has already started is waited for to its end, and this one waits on nothing: it disables,
    /// invalidates and stops timers.
    ///
    /// True when the taps' own thread did it, false when it had to be done from here.
    @discardableResult
    public func shutDown() -> Bool {
        isShutDown.withLock { $0 = true }
        if thread.performAndWait(timeout: K.shutDownWait, { [weak self] in self?.feed(.terminate) }) { return true }
        Log.click.error("the taps' thread did not answer in \(K.shutDownWait, privacy: .public) s; taps destroyed from the calling thread")
        destroyFromAnyThread()
        // Should that thread come back, the lifecycle still has to hear that it is over. `isShutDown` is what
        // holds until it does, and if it never does.
        thread.perform { [weak self] in self?.feed(.terminate) }
        return false
    }

    // MARK: - The lifecycle, on the tap's thread

    private func feed(_ event: TapLifecycle.Event) {
        assert(thread.isCurrent)
        for effect in lifecycle.handle(event, now: Self.now()) { run(effect) }
    }

    /// For an event heard inside a tap's callback that may disable or destroy that very tap. It is fed once
    /// the callback has returned, which is when the answer about the event in hand is sent: a tap disabled
    /// with its own event still unanswered leaves it to the window server what becomes of that event, and a
    /// swallowed release that reaches Finder after all undoes the range. The run loop runs these blocks
    /// before it looks at another port, so nothing is heard in between.
    private func feedAfterThisCallback(_ event: TapLifecycle.Event) {
        thread.perform { [weak self] in self?.feed(event) }
    }

    /// Seconds that only go forwards. Core never reads a clock, so this is where the time comes from.
    private static func now() -> TimeInterval {
        TimeInterval(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    private func run(_ effect: TapLifecycle.Effect) {
        switch effect {
        case .createTaps:
            // After `shutDown` the lifecycle is told it is over, not that macOS refused: the one would be a
            // line in the log about a refusal that never happened.
            guard !isShutDown.withLock({ $0 }) else { feed(.terminate); return }
            let created = createTaps()
            feed(!created && isShutDown.withLock({ $0 }) ? .terminate : .tapsCreated(created))
        case .destroyTaps:
            destroyTaps()
        case .enableClickTap:
            guard let click else { return }
            guard !isShutDown.withLock({ $0 }) else { return }
            CGEvent.tapEnable(tap: click, enable: true)
            // A tap that stays disabled when it is asked not to be is what a grant that has just gone looks
            // like from this side. It counts as one more time the system took it away, and it is heard once
            // this callback has returned: the third of them destroys both taps, and arming can come out of the
            // sentinel's own callback.
            if !CGEvent.tapIsEnabled(tap: click) {
                Log.click.error("the click tap did not take the enable")
            }
        case .disableClickTap:
            if let click { CGEvent.tapEnable(tap: click, enable: false) }
        case .enableSentinel:
            if let sentinel { CGEvent.tapEnable(tap: sentinel, enable: true) }
        case .probeTrust(let generation):
            hooks.probeTrust { [weak self] verdict in
                self?.thread.perform { self?.feed(.trustProbe(verdict, generation: generation)) }
            }
        case .recheckTrustSoon:
            scheduleRechecks()
        case .startWatchdog:
            startWatchdog()
        case .stopWatchdog:
            stopWatchdog()
        case .checkStillAway:
            hooks.checkStillAway()
        case .report(let status):
            hooks.statusChanged(status)
        case .log(let level, let line):
            switch level {
            case .debug: Log.click.debug("\(line, privacy: .public)")
            case .notice: Log.click.notice("\(line, privacy: .public)")
            case .error: Log.click.error("\(line, privacy: .public)")
            }
        }
    }

    // MARK: - The taps

    private static let sentinelMask: CGEventMask =
        (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)
    private static let clickMask: CGEventMask =
        (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)

    /// Both or neither. False is what a missing grant looks like, and it is the only signal there is.
    private func createTaps() -> Bool {
        guard !isShutDown.withLock({ $0 }) else { return false }
        let owner = Unmanaged.passUnretained(self).toOpaque()
        guard let sentinel = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            // A listener: the window server does not wait for it, so it can hold nothing up.
            options: .listenOnly,
            eventsOfInterest: Self.sentinelMask,
            callback: { _, type, event, owner in
                if let owner {
                    Unmanaged<ClickGuard>.fromOpaque(owner).takeUnretainedValue().sentinelHeard(type, event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: owner
        ) else { return false }

        guard let click = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            // Not a listener: swallowing the click is the whole point, and what makes this tap dangerous.
            options: .defaultTap,
            eventsOfInterest: Self.clickMask,
            callback: { _, type, event, owner in
                guard let owner else { return Unmanaged.passUnretained(event) }
                return Unmanaged<ClickGuard>.fromOpaque(owner).takeUnretainedValue().clickHeard(type, event)
            },
            userInfo: owner
        ) else {
            CFMachPortInvalidate(sentinel)
            return false
        }
        // A tap is born enabled. This one is disabled before anything else is done with it, and stays that
        // way until the lifecycle says ⇧ Shift is down and the grant has just been vouched for.
        CGEvent.tapEnable(tap: click, enable: false)
        // Reachable from here on by a teardown that cannot wait for this thread.
        ports.withLockUnchecked { $0 = Ports(sentinel: sentinel, click: click) }

        // A tap whose port is on no run loop is a tap nobody answers: every click routed to it would stall
        // until the system's timeout, and the notice that it had been disabled would arrive through the same
        // unanswered port. So a source that cannot be made takes both taps with it.
        var made: [CFRunLoopSource] = []
        for port in [sentinel, click] {
            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else { break }
            made.append(source)
        }
        // And nothing is listened for once `shutDown` has been called, however far this had got.
        guard made.count == 2, !isShutDown.withLock({ $0 }) else {
            CGEvent.tapEnable(tap: sentinel, enable: false)
            CFMachPortInvalidate(click)
            CFMachPortInvalidate(sentinel)
            ports.withLockUnchecked { $0 = Ports() }
            return false
        }
        for source in made { CFRunLoopAddSource(thread.cfRunLoop, source, .commonModes) }
        sources = made
        CGEvent.tapEnable(tap: sentinel, enable: true)
        self.sentinel = sentinel
        self.click = click
        return true
    }

    private func destroyTaps() {
        stopWatchdog()
        cancelRechecks()
        // The dangerous one first.
        for port in [click, sentinel] {
            guard let port else { continue }
            CGEvent.tapEnable(tap: port, enable: false)
        }
        for source in sources { CFRunLoopRemoveSource(thread.cfRunLoop, source, .commonModes) }
        for port in [click, sentinel] {
            guard let port else { continue }
            CFMachPortInvalidate(port)
        }
        sources = []
        click = nil
        sentinel = nil
        ports.withLockUnchecked { $0 = Ports() }
    }

    /// Disabling and invalidating are messages to the window server and are honoured from any thread. The
    /// run loop sources are left to die with their ports: they belong to a thread this one does not own.
    private func destroyFromAnyThread() {
        let ports = self.ports.withLockUnchecked { ports -> Ports in
            defer { ports = Ports() }
            return ports
        }
        for port in [ports.click, ports.sentinel] {
            guard let port else { continue }
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
    }

    // MARK: - What the taps hear

    private func sentinelHeard(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout:
            feedAfterThisCallback(.tapDisabledBySystem(.sentinel, .timeout))
        case .tapDisabledByUserInput:
            feedAfterThisCallback(.tapDisabledBySystem(.sentinel, .userInput))
        case .flagsChanged:
            feed(Self.modifiers(event.flags))
        case .leftMouseDown:
            let flags = event.flags
            // A press carries the modifier keys as they are, which covers a key event that was never heard.
            feed(Self.modifiers(flags))
            // A plain click and a ⌘ Command click set the anchor, and so does ⌘ Command with ⇧ Shift, which
            // is Finder's own toggle and passes through the click tap (docs/functional.md §2.1). Only a
            // plain ⇧ Shift press is not noted here: it is the click the worker decides.
            if !flags.contains(.maskShift) || flags.contains(.maskCommand) { hooks.plainClick(event.location) }
        default:
            break
        }
    }

    private func clickHeard(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout:
            // **Never enabled again from here.** The system disables a tap that stopped answering, and that
            // is the net under everything else in this file.
            feedAfterThisCallback(.tapDisabledBySystem(.click, .timeout))
            return pass
        case .tapDisabledByUserInput:
            feedAfterThisCallback(.tapDisabledBySystem(.click, .userInput))
            return pass
        case .leftMouseDown:
            let flags = event.flags
            let number = event.getIntegerValueField(.mouseEventNumber)
            let ours = lifecycle.phase == .armed && flags.contains(.maskShift)
                // ⌥ Option and ⌃ Control mean something else in Finder. Neither is ours to take.
                && !flags.contains(.maskAlternate) && !flags.contains(.maskControl)
            guard ours else {
                feed(.pressDecided(number: number, swallowed: false))
                // A press without ⇧ Shift on a tap that is only enabled while it is held: its release was
                // never heard. The lifecycle disarms on this, once this press has been answered.
                feedAfterThisCallback(Self.modifiers(flags))
                return pass
            }
            let swallow = hooks.decidePress(event.location, flags)
            feed(.pressDecided(number: number, swallowed: swallow))
            return swallow ? nil : pass
        case .leftMouseUp:
            // Finder never saw the press that was swallowed, and would apply its own ⇧ Shift toggle to the
            // clicked file if it were handed the release. Only that release: the two carry the same number.
            let number = event.getIntegerValueField(.mouseEventNumber)
            let swallow = lifecycle.shouldSwallowRelease(number)
            // With ⇧ Shift already up this is what disarms, so it waits for the release to be answered.
            feedAfterThisCallback(.releaseSeen(number: number))
            return swallow ? nil : pass
        default:
            return pass
        }
    }

    private static func modifiers(_ flags: CGEventFlags) -> TapLifecycle.Event {
        .modifiers(shift: flags.contains(.maskShift),
                   optionOrControl: flags.contains(.maskAlternate) || flags.contains(.maskControl))
    }

    // MARK: - The watch kept while armed, and the looks after a notification

    /// A timer that exists only while the click tap is enabled. It asks the keyboard, not the event stream,
    /// whether the keys still ask for it: a release, or an ⌥ Option or ⌃ Control press, that the sentinel
    /// never heard is otherwise a tap left enabled.
    private func startWatchdog() {
        stopWatchdog()
        armedActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "the click tap is enabled")
        let interval = K.armedWatchInterval
        guard let timer = CFRunLoopTimerCreateWithHandler(
            kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + interval, interval, 0, 0, { [weak self] _ in
            guard let self else { return }
            let hardware = CGEventSource.flagsState(.hidSystemState)
            let session = CGEventSource.flagsState(.combinedSessionState)
            // Down if either says so. A key held on another Mac through a sharing tool never reaches the
            // hardware state, so that state alone would disarm under everybody who works that way. The price
            // is a session that has stalled and still says down: that case is left to the live question this
            // same look asks, and under it to the system's own timeout.
            let shiftDown = hardware.contains(.maskShift) || session.contains(.maskShift)
            // Down if either says so as well, and there that is the cautious way round: it disarms.
            let optionOrControlDown = [hardware, session].contains {
                $0.contains(.maskAlternate) || $0.contains(.maskControl)
            }
            let buttonDown = CGEventSource.buttonState(.hidSystemState, button: .left)
                || CGEventSource.buttonState(.combinedSessionState, button: .left)
            self.feed(.watchdog(shiftDown: shiftDown, optionOrControlDown: optionOrControlDown,
                                buttonDown: buttonDown))
        }) else {
            // No watch, no armed tap: reported as a key that is up, which is what disarms.
            Log.click.error("the watch over the armed tap could not be created; disarming")
            feedAfterThisCallback(.watchdog(shiftDown: false, optionOrControlDown: false, buttonDown: false))
            return
        }
        CFRunLoopAddTimer(thread.cfRunLoop, timer, .commonModes)
        watchdog = timer
    }

    private func stopWatchdog() {
        if let watchdog { CFRunLoopTimerInvalidate(watchdog) }
        watchdog = nil
        if let armedActivity { ProcessInfo.processInfo.endActivity(armedActivity) }
        armedActivity = nil
    }

    /// A few looks after an event, and then nothing: never a poll.
    private func scheduleRechecks() {
        cancelRechecks()
        for delay in K.trustRecheckDelays {
            guard let timer = CFRunLoopTimerCreateWithHandler(
                kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + delay, 0, 0, 0, { [weak self] _ in
                    self?.hooks.probeTrust { verdict in
                        self?.thread.perform { self?.feed(.trustRecheck(verdict)) }
                    }
                }) else { continue }
            CFRunLoopAddTimer(thread.cfRunLoop, timer, .commonModes)
            rechecks.append(timer)
        }
    }

    private func cancelRechecks() {
        for timer in rechecks { CFRunLoopTimerInvalidate(timer) }
        rechecks = []
    }
}
