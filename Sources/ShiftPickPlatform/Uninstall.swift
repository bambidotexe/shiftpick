import AppKit
import Foundation
import ShiftPickCore

/// Which part of taking ShiftPick off a Mac did not work. The words a user reads are the app target's:
/// this one only says which step, and what the system said about it.
public enum UninstallStep: Sendable, Hashable {
    case accessibilityGrant
    case loginItem
    case bundleToTrash
    case storedState
    /// The helper was never started: what it would have removed could not be shown to be this app's own.
    case storedStateNotProvablyOurs
    /// The login item's service did not answer within `K.uninstallStepWait`.
    case loginItemNoAnswer
}

public struct UninstallFailure: Sendable, Hashable {
    public let step: UninstallStep
    public let reason: String
    public init(step: UninstallStep, reason: String) {
        self.step = step
        self.reason = reason
    }
}

/// Everything ShiftPick put on a Mac outside its own bundle, taken off.
///
/// **Only what is ShiftPick's own, and only through the system's own tools.** The answer the user once gave
/// to "may ShiftPick send notifications" stays where macOS keeps it: no public API gives it back, and the
/// way around that is to rewrite another program's private database and kill two system daemons, which is
/// not a thing an uninstall gets to do to somebody's Mac. A reinstall inherits that answer.
///
/// **Dragging the bundle to the Trash is not an uninstall.** It removes the app and nothing else: the login
/// item registered with `SMAppService` stays, so System Settings › General › Login Items goes on listing an
/// app that is not there and offering to start it, and the Accessibility grant stays in the privacy list,
/// where a later build signed by the same team inherits a decision nobody remembers making.
public enum Uninstall {
    /// The grant and the login item, in that order, while the bundle they both name is still where they
    /// name it. `tccutil reset` against a bundle identifier with no bundle behind it fails, and nothing
    /// puts that right afterwards, so this runs before the app goes anywhere.
    ///
    /// **Blocking, and never on the main thread.** Each step waits on another process, `K.uninstallStepWait`
    /// at most, without running anything else meanwhile (`BoundedWait`); a step that does not answer in time
    /// is reported failed and the uninstall goes on. Each one is logged with how long it took.
    public static func removeSystemRegistrations() -> [UninstallFailure] {
        dispatchPrecondition(condition: .notOnQueue(.main))
        var failed: [UninstallFailure] = []
        let bundleIdentifier = AppIdentity.bundleIdentifier

        let reset = timed("the Accessibility grant reset") {
            BoundedWait.run("/usr/bin/tccutil", ["reset", "Accessibility", bundleIdentifier],
                            timeout: K.uninstallStepWait)
        }
        // `tccutil reset` exits non-zero when it has nothing to reset as well as when it fails, so a grant
        // that was never given reads as a failure here. The sentence the user reads names where to look,
        // which is true either way.
        if reset != .exited(0) { failed.append(.init(step: .accessibilityGrant, reason: "")) }

        if timed("the login item's state", { LoginItem.isEnabled }) {
            switch timed("the login item removal", { LoginItem.remove(within: K.uninstallStepWait) }) {
            case .removed: break
            case .failed(let reason): failed.append(.init(step: .loginItem, reason: reason))
            case .noAnswer: failed.append(.init(step: .loginItemNoAnswer, reason: ""))
            }
        }
        return failed
    }

    /// One line per step, with what came back and how long it took: the next time a step is slow, the log
    /// says which one.
    private static func timed<T>(_ step: String, _ body: () -> T) -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = body()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        Log.app.notice("uninstall: \(step, privacy: .public): \(String(describing: result), privacy: .public) in \(Int(ms), privacy: .public) ms")
        return result
    }

    /// The Trash, not a delete: the app the user has just removed is still there to put back.
    @MainActor
    public static func moveBundleToTrash(_ completion: @escaping @MainActor (UninstallFailure?) -> Void) {
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, error in
            let failure = error.map { UninstallFailure(step: .bundleToTrash, reason: $0.localizedDescription) }
            DispatchQueue.main.async { completion(failure) }
        }
    }

    /// The preferences and the support folder, handed to a process that outlives this one, and started just
    /// before the quit. `UninstallPlan` says why they cannot be removed here.
    @MainActor
    public static func startHelper() -> UninstallFailure? {
        guard let script = UninstallPlan.helperScript(
            pid: getpid(), supportDirectory: Paths.appSupport.path,
            bundleIdentifier: AppIdentity.bundleIdentifier,
            home: FileManager.default.homeDirectoryForCurrentUser.path)
        else {
            // Nothing is removed rather than something that might not be this app's.
            Log.app.error("""
                the uninstall helper was not started: \(Paths.appSupport.path, privacy: .public) or \
                \(AppIdentity.bundleIdentifier, privacy: .public) is not provably this app's own
                """)
            return .init(step: .storedStateNotProvablyOurs, reason: "")
        }
        do {
            try DetachedProcess.spawn(executable: "/bin/sh", arguments: ["-c", script], environment: [:])
            return nil
        } catch {
            return .init(step: .storedState, reason: "\(error)")
        }
    }

}
