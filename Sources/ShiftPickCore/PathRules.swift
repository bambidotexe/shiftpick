import Foundation

/// What a path has to look like before a helper that deletes or renames is pointed at it.
///
/// Both of the app's helpers, the uninstall's and the update's, run after the app has quit, with nobody left
/// to stop them, and both are handed paths glued together from strings the bundle and the system supplied.
/// These are the questions asked of every one of those paths first, and they are asked of the text alone: no
/// disk is read, so a test can ask them of `/` without owning it.
enum PathRules {
    /// An absolute path in its plainest form, and not the root: no `..` to climb with, no `.`, no doubled or
    /// trailing slash for two spellings of one folder to hide behind.
    static func isPlainAbsolute(_ path: String) -> Bool {
        guard path.hasPrefix("/"), path != "/" else { return false }
        return path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    /// Strictly inside `folder`, both of them plain.
    static func isInside(_ path: String, folder: String) -> Bool {
        isPlainAbsolute(path) && isPlainAbsolute(folder) && path.hasPrefix(folder + "/")
    }

    /// One component of a path: a name, which may have spaces in it, and nothing that climbs or descends.
    static func isOneComponent(_ text: String) -> Bool {
        !text.isEmpty && text != "." && text != ".." && !text.contains("/")
            && !text.unicodeScalars.contains { CharacterSet.newlines.contains($0) }
    }

    /// One component that is also one word of a line: a line somebody will split on spaces.
    static func isOneWord(_ text: String) -> Bool {
        isOneComponent(text) && !text.unicodeScalars.contains { CharacterSet.whitespaces.contains($0) }
    }
}
