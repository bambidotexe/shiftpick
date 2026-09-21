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
    @MainActor
    public static func removeSystemRegistrations() -> [UninstallFailure] {
        var failed: [UninstallFailure] = []
        let bundleIdentifier = AppIdentity.bundleIdentifier
        if !resetAccessibilityGrant(bundleIdentifier) {
            failed.append(.init(step: .accessibilityGrant, reason: ""))
        }
        if LoginItem.isEnabled {
            do { try LoginItem.setEnabled(false) }
            catch { failed.append(.init(step: .loginItem, reason: error.localizedDescription)) }
        }
        return failed
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
            return .init(step: .storedState, reason: Loc.settings.general.uninstallRefusedReason)
        }
        do {
            try DetachedProcess.spawn(executable: "/bin/sh", arguments: ["-c", script], environment: [:])
            return nil
        } catch {
            return .init(step: .storedState, reason: "\(error)")
        }
    }

    /// `tccutil reset` exits non-zero when it has nothing to reset as well as when it fails, so a grant
    /// that was never given reads as a failure here. The caller shows a sentence naming where to look,
    /// which is true either way.
    private static func resetAccessibilityGrant(_ bundleIdentifier: String) -> Bool {
        run("/usr/bin/tccutil", ["reset", "Accessibility", bundleIdentifier]) == 0
    }

    @discardableResult
    private static func run(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
