import Foundation

/// The two places ShiftPick writes outside its own bundle, and nothing else. Both are under one folder, so
/// the uninstall has one thing to remove.
public enum Paths {
    /// `~/Library/Application Support/ShiftPick`.
    public static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppIdentity.name, isDirectory: true)
    }

    /// The marker an installer writes so that the launch it is about to make opens no window.
    public static var quietLaunch: URL { appSupport.appendingPathComponent("quiet-launch") }

    /// Where an update is fetched and unpacked. Inside `appSupport`, so removing that folder takes a
    /// half-fetched disk image and a finished install's leftovers with it.
    public static var updates: URL { appSupport.appendingPathComponent("updates", isDirectory: true) }
}
