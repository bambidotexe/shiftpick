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
    ///
    /// **nil when anything it would be pointed at is not provably this app's own.** The helper runs `rm -rf`,
    /// and every path below is glued together from three strings the bundle supplied. An identifier that
    /// came back empty turns `~/Library/Caches/<identifier>` into the user's whole Caches folder; a name that
    /// came back empty does the same to Application Support. Neither can happen to a bundle this project
    /// built, and a helper that deletes is not the place to rely on that.
    public static func helperScript(pid: Int32, supportDirectory: String, bundleIdentifier: String,
                                    home: String) -> String? {
        guard isBundleIdentifier(bundleIdentifier), isHomeFolder(home),
              isOwnFolder(supportDirectory, inApplicationSupportOf: home) else { return nil }
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
            "/usr/bin/defaults delete \(shellQuoted(bundleIdentifier)) 2>/dev/null",
            "/bin/rm -rf " + paths.map(shellQuoted).joined(separator: " "),
            // One per host identifier, so a glob rather than a path; `find` keeps the glob away from a home
            // folder whose name has a space in it.
            "/usr/bin/find \(shellQuoted(library + "/Preferences/ByHost")) -maxdepth 1 -name \(shellQuoted(bundleIdentifier + ".*.plist")) -delete 2>/dev/null",
        ] as [String]).joined(separator: "\n") + "\n"
    }

    // MARK: - What the helper may be pointed at

    /// Letters, digits and hyphens in two or more parts joined by dots, and nothing else: no slash that
    /// would climb out of a folder, no space or quote for the shell to read, no empty part.
    static func isBundleIdentifier(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { scalar in
                scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-")
            }
        }
    }

    static func isHomeFolder(_ path: String) -> Bool { PathRules.isPlainAbsolute(path) }

    /// Exactly one folder of the app's own, directly inside that home's Application Support.
    static func isOwnFolder(_ path: String, inApplicationSupportOf home: String) -> Bool {
        let parent = home + "/Library/Application Support/"
        guard path.hasPrefix(parent) else { return false }
        return PathRules.isOneComponent(String(path.dropFirst(parent.count)))
    }

    /// Single quotes, with any quote in the path closed and reopened around an escaped one. The home folder
    /// is the user's to name, spaces and all.
    public static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
