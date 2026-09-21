import AppKit
import ShiftPickCore

/// The run loop is AppKit's, not SwiftUI's. The status item is added and removed by `MenuBarController` as
/// the user's choice changes, and a `MenuBarExtra` cannot be: a scene re-reads its `isInserted` binding
/// only when SwiftUI re-evaluates the scene, which a change published from elsewhere does not cause.
/// Nothing is lost by owning the loop: the Settings window, the onboarding window and the update window are
/// `NSHostingController`s already.
@main
enum ShiftPickMain {
    /// `NSApplication.delegate` is a weak reference, so the delegate is held here for the process's
    /// lifetime.
    @MainActor private static var delegate: AppDelegate?

    @MainActor static func main() {
        // Before anything is built. The menu and the windows all read the ambient language, and nothing
        // here may show a sentence chosen before it is set. Core holds the rule; this is the only place
        // that asks the system.
        Loc.language = Language(preferredLanguage: Locale.preferredLanguages.first)

        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        // Stated here as well as by `Info.plist`'s `LSUIElement`, so a binary run straight out of `.build`
        // — where no bundle is read — is an accessory too, with no Dock icon and no menu bar of its own.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
