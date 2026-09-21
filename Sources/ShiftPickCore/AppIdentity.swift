import Foundation

/// What the app calls itself, read from the bundle it is running out of.
///
/// **`scripts/signing.env` is the one place these are written.** `scripts/make-app.sh` puts `APP_NAME`,
/// `BUNDLE_ID` and `GITHUB_REPO` into the built `Info.plist`, and this reads them back, so renaming the app
/// is that file and the four names SwiftPM cannot read from it: the directories under `Sources/` and
/// `Tests/`, and the target names in `Package.swift`.
///
/// The literals below are the fallback for a binary run outside a bundle — `swift run`, a unit test — where
/// there is no `Info.plist` to read. They are never what a shipped build uses.
public enum AppIdentity {
    /// The name every sentence the user reads spells out. Never translated.
    public static let name: String = string("CFBundleName") ?? "ShiftPick"

    public static let bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "dev.rubens.ShiftPick"

    /// Empty for a binary run outside its bundle, which `UpdateCheck.decide` reads as up to date: offering
    /// that an update would be offering it to everything.
    public static let version: String = string("CFBundleShortVersionString") ?? ""

    /// `owner/repo`, the only thing the update check needs to build its URL.
    public static let repository: String = string("SPUpdateRepository") ?? "bambidotexe/shiftpick"

    /// The subsystem every `Logger` in the app logs under, which is the bundle identifier by convention so
    /// that one `log` predicate catches everything this app says.
    public static var logSubsystem: String { bundleIdentifier }

    private static func string(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty
        else { return nil }
        return value
    }
}
