import Foundation

/// What taking ShiftPick off a Mac has to remove, and the part of it that can only happen once this process
/// has gone.
///
/// **Dragging the bundle to the Trash is not an uninstall.** It removes the app and nothing else: the login
/// item registered with `SMAppService` stays, so System Settings › General › Login Items goes on listing an
/// app that is not there and offering to start it, and the Accessibility grant stays in the privacy list,
/// where a later build signed by the same team inherits a decision nobody remembers making.
public enum UninstallPlan {
    /// How long the helper waits for this process to go before giving up, in tenths of a second. A helper
    /// that could spin for ever is worse than one that stops: what it does after the wait is a handful of
    /// removals of paths nothing holds open.
    public static let helperWaitTenths = 600

    /// What is left of ShiftPick after an uninstall, for a check that it really has gone: the bundle, the
    /// preferences domain and the support folder.
    public static func remains(bundlePath: String, bundleIdentifier: String, supportDirectory: String) -> [String] {
        [bundlePath, bundleIdentifier, supportDirectory]
    }

    /// The preferences and the support folder, **handed to a process that outlives this one.**
    ///
    /// Removing them in the app does not work: `cfprefsd` writes the domain out again as the process exits
    /// whatever happens, leaving an empty plist where a Mac that never had ShiftPick has no file at all. So
    /// the helper waits for the pid.
    ///
    /// The caches, the HTTP storage and the saved window state go too. They are not dangerous, but they are
    /// named after the bundle identifier and belong to nothing else, and an uninstall that leaves them is
    /// not the fresh Mac it claims to be.
    public static func helperScript(pid: Int32, supportDirectory: String, bundleIdentifier: String,
                                    home: String) -> String {
        let library = home + "/Library"
        let paths = [
            supportDirectory,
            "\(library)/Preferences/\(bundleIdentifier).plist",
            "\(library)/Caches/\(bundleIdentifier)",
            "\(library)/HTTPStorages/\(bundleIdentifier)",
            "\(library)/HTTPStorages/\(bundleIdentifier).binarycookies",
            "\(library)/Saved Application State/\(bundleIdentifier).savedState",
        ]
        return ([
            "i=0",
            "while /bin/kill -0 \(pid) 2>/dev/null && [ $i -lt \(helperWaitTenths) ]; do /bin/sleep 0.1; i=$((i+1)); done",
            // Before the file is removed, or cfprefsd writes its cache back over the gap.
            "/usr/bin/defaults delete \(bundleIdentifier) 2>/dev/null",
            "/bin/rm -rf " + paths.map(shellQuoted).joined(separator: " "),
            // One per host identifier, so a glob rather than a path; `find` keeps the glob away from a home
            // folder whose name has a space in it.
            "/usr/bin/find \(shellQuoted(library + "/Preferences/ByHost")) -maxdepth 1 -name \(shellQuoted(bundleIdentifier + ".*.plist")) -delete 2>/dev/null",
        ] as [String]).joined(separator: "\n") + "\n"
    }

    /// Single quotes, with any quote in the path closed and reopened around an escaped one. The home folder
    /// is the user's to name, spaces and all.
    public static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
