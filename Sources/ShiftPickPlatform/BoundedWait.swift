import Foundation
import os

/// Waiting on something this app does not own, another process or a daemon's reply, **for so long and no
/// longer, and without running anything else meanwhile.**
///
/// `Process.waitUntilExit()` runs the calling thread's run loop until the tool is done. On the main thread
/// that re-runs the app's own timers, notifications and view updates in the middle of whatever was waiting,
/// and the uninstall that waited that way for `tccutil` froze for a minute (`docs/pitfalls.md` 16). Both waits
/// here block the calling thread and nothing else, so **neither is ever called on the main thread**.
public enum BoundedWait {
    public enum ProcessOutcome: Equatable, Sendable {
        case exited(Int32)
        /// Still running at the deadline, and stopped.
        case timedOut
        case couldNotStart
    }

    /// Runs a tool to its end, or to `timeout`, whichever comes first. It reads nothing and writes nowhere.
    public static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) -> ProcessOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let ended = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in ended.signal() }
        do { try process.run() } catch { return .couldNotStart }
        guard ended.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            // Reaped rather than left behind: the handler still runs once it has gone.
            _ = ended.wait(timeout: .now() + 1)
            return .timedOut
        }
        return .exited(process.terminationStatus)
    }

    /// Starts a call that answers through a callback and waits for the first answer, for `timeout` at most.
    /// nil when none came in time; an answer that comes later is dropped.
    public static func answer<T: Sendable>(within timeout: TimeInterval,
                                           _ start: (@escaping @Sendable (T) -> Void) -> Void) -> T? {
        let box = OSAllocatedUnfairLock<T?>(initialState: nil)
        let answered = DispatchSemaphore(value: 0)
        start { value in
            box.withLock { if $0 == nil { $0 = value } }
            answered.signal()
        }
        guard answered.wait(timeout: .now() + timeout) == .success else { return nil }
        return box.withLock { $0 }
    }
}
