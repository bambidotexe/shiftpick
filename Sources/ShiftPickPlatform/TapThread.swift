import Foundation
import os

/// The thread the event taps are served on, and nothing else is.
///
/// **An event tap that can swallow a click holds up every click on the Mac for as long as its callback has
/// not answered**, and a callback is answered by whichever run loop the tap's source was added to. On the main
/// run loop that is the thread that also lays out windows, runs alerts, waits for `tccutil` and draws SwiftUI:
/// every stall of the interface becomes a stall of the mouse. This thread has one job, so the only thing that
/// can delay an answer is the answer itself, and `DeadlineGate` bounds that.
///
/// Everything that touches a tap happens here, so the taps, their lifecycle and their timers need no lock:
/// other threads hand their work over with `perform`.
public final class TapThread: @unchecked Sendable {
    /// What the thread publishes about itself, written once before `ready` is signalled.
    private final class Started: @unchecked Sendable {
        var runLoop: CFRunLoop?
    }

    private let thread: Thread
    private let runLoop: CFRunLoop

    public init(name: String) {
        let started = Started()
        let ready = DispatchSemaphore(value: 0)
        thread = Thread {
            let runLoop = CFRunLoopGetCurrent()
            // A run loop with no source returns at once. This one never fires; it is only there so the loop
            // has something to wait on before the taps exist and after they have gone.
            var context = CFRunLoopSourceContext()
            let keepAlive = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)
            CFRunLoopAddSource(runLoop, keepAlive, .commonModes)
            started.runLoop = runLoop
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = name
        // The Mac's clicks wait on this thread while the click tap is armed.
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        runLoop = started.runLoop!
    }

    public var isCurrent: Bool { Thread.current === thread }

    /// The thread's own run loop, for the sources and timers that live on it.
    var cfRunLoop: CFRunLoop { runLoop }

    /// Runs `block` on the thread, after whatever was handed over before it.
    public func perform(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    /// Runs `block` on the thread and waits for it. **True when it ran; false when it did not and never
    /// will**, which is what lets a caller that cannot wait any longer do the work itself without the same
    /// work happening a second time behind its back. A block that has already started is always waited for.
    @discardableResult
    public func performAndWait(timeout: TimeInterval, _ block: @escaping () -> Void) -> Bool {
        if isCurrent {
            block()
            return true
        }
        enum Claim { case unclaimed, running, cancelled }
        let claim = OSAllocatedUnfairLock(initialState: Claim.unclaimed)
        let done = DispatchSemaphore(value: 0)
        perform {
            let mine = claim.withLock { state -> Bool in
                guard state == .unclaimed else { return false }
                state = .running
                return true
            }
            guard mine else { return }
            block()
            done.signal()
        }
        if done.wait(timeout: .now() + timeout) == .success { return true }
        let cancelled = claim.withLock { state -> Bool in
            guard state == .unclaimed else { return false }
            state = .cancelled
            return true
        }
        if cancelled { return false }
        done.wait()
        return true
    }

    /// Ends the thread. The app never does: its taps live as long as the process. Tests do.
    public func stop() {
        CFRunLoopStop(runLoop)
    }
}
