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
        _ = resetNotificationGrant(bundleIdentifier)
        return failed
    }

    /// Notification authorization lives in usernoted's group preferences, and no public API puts it back to
    /// "not asked yet". Left behind, a reinstall inherits a decision the user made once about an app they
    /// have since removed, and can never be asked again. Its failure is not worth a sentence: an update
    /// this app cannot announce is the whole of the cost.
    private static func resetNotificationGrant(_ bundleIdentifier: String) -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/Library/Preferences/group.com.apple.usernoted.plist")
        guard let data = try? Data(contentsOf: url),
              var plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let apps = plist["apps"] as? [[String: Any]] else { return false }
        let kept = apps.filter { ($0["bundle-id"] as? String) != bundleIdentifier }
        guard kept.count != apps.count else { return true }
        plist["apps"] = kept
        guard let out = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0),
              (try? out.write(to: url)) != nil else { return false }
        for daemon in ["usernoted", "NotificationCenter"] { run("/usr/bin/killall", [daemon]) }
        return true
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
        let script = UninstallPlan.helperScript(pid: getpid(),
                                                supportDirectory: Paths.appSupport.path,
                                                bundleIdentifier: AppIdentity.bundleIdentifier,
                                                home: FileManager.default.homeDirectoryForCurrentUser.path)
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
