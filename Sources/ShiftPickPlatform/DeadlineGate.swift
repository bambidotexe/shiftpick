import Foundation
import os

/// One held click, as the worker sees it: whether anybody is still waiting for the answer, and the one
/// moment at which the answer becomes irreversible.
///
/// The order a worker follows is fixed: read everything, then `commit()`, then set the selection, then
/// `finish(swallow: true)`. **`commit()` is the point of no return, and it can be refused**: when the waiter
/// has already given the click back to the system, setting a selection now would land on top of whatever
/// Finder did with that click, so the worker stops instead.
public final class ClickTicket: @unchecked Sendable {
    private enum State: Equatable {
        case pending
        /// The selection is being set right now.
        case committing
        /// Nobody is waiting any more.
        case abandoned
        case finished(swallow: Bool)
    }

    private let state = OSAllocatedUnfairLock(initialState: State.pending)
    private let answered = DispatchSemaphore(value: 0)

    /// True once the click has been given back to the system. Work that reads many things looks at this
    /// between two of them, so a Finder that has stopped answering is not asked a hundred more questions on
    /// behalf of a click that is already gone.
    public var isAbandoned: Bool { state.withLock { $0 == .abandoned } }

    /// Asks to do the irreversible part. False when the waiter has given up: do nothing, and return.
    public func commit() -> Bool {
        state.withLock { state in
            guard state == .pending else { return false }
            state = .committing
            return true
        }
    }

    /// The answer. **A swallow is only honoured after a `commit()` that was granted**: a click is swallowed
    /// because a selection was set, and for no other reason.
    public func finish(swallow: Bool) {
        let signal = state.withLock { state -> Bool in
            switch state {
            case .pending:
                state = .finished(swallow: false)
                return true
            case .committing:
                state = .finished(swallow: swallow)
                return true
            case .abandoned, .finished:
                return false
            }
        }
        if signal { answered.signal() }
    }

    /// Waits for the answer: `budget`, and `grace` more only if the selection is being set at that moment.
    fileprivate func wait(budget: TimeInterval, grace: TimeInterval) -> DeadlineGate.Outcome {
        if answered.wait(timeout: .now() + budget) == .timedOut {
            let selecting = state.withLock { state -> Bool in
                if state == .pending { state = .abandoned }
                return state == .committing
            }
            if selecting, answered.wait(timeout: .now() + grace) == .timedOut {
                let stillSelecting = state.withLock { state -> Bool in
                    guard state == .committing else { return false }
                    state = .abandoned
                    return true
                }
                if stillSelecting { return .outOfTimeWhileSelecting }
            }
        }
        return state.withLock { state in
            if case .finished(let swallow) = state { return .answered(swallow: swallow) }
            return .outOfTime
        }
    }
}

/// Hands a held click to the worker and waits **so long and no longer**.
///
/// **The budget belongs to the waiter, never to the work.** Work that checks its own clock between steps
/// keeps no promise when one Accessibility call does not return. So the tap's thread sleeps on a semaphore
/// with a timeout, and when that runs out the click goes back to the system whatever the worker is doing. The
/// worker finds out from its ticket.
public final class DeadlineGate: @unchecked Sendable {
    public enum Outcome: Equatable, Sendable {
        case answered(swallow: Bool)
        /// The worker is still busy with an earlier click, so this one was not handed over at all.
        case busy
        case outOfTime
        /// Out of time with the selection half set: the click went to Finder on top of it.
        case outOfTimeWhileSelecting

        public var swallow: Bool { self == .answered(swallow: true) }
    }

    private let queue: DispatchQueue
    private let busy = OSAllocatedUnfairLock(initialState: false)

    public init(queue: DispatchQueue) {
        self.queue = queue
    }

    /// **A click never queues.** A worker still stuck on the click before would make this one wait for an
    /// answer about something that is no longer on screen, so it is refused at once and goes to Finder.
    public func run(budget: TimeInterval, grace: TimeInterval,
                    _ work: @escaping (ClickTicket) -> Void) -> Outcome {
        let free = busy.withLock { busy -> Bool in
            guard !busy else { return false }
            busy = true
            return true
        }
        guard free else { return .busy }

        let ticket = ClickTicket()
        queue.async { [busy] in
            work(ticket)
            // Work that ends without a word has decided nothing.
            ticket.finish(swallow: false)
            busy.withLock { $0 = false }
        }
        return ticket.wait(budget: budget, grace: grace)
    }
}
