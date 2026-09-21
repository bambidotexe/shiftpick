import AppKit
import ShiftPickCore
import ShiftPickPlatform

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

        leaveIfAlreadyRunning()

        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        // Stated here as well as by `Info.plist`'s `LSUIElement`, so a binary run straight out of `.build`
        // — where no bundle is read — is an accessory too, with no Dock icon and no menu bar of its own.
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// **One ShiftPick, one pair of event taps.** A second copy, a bundle left in a build folder that
    /// Spotlight offers, `open -n`, would put a second click tap on the same clicks: two apps each deciding
    /// what a ⇧ Shift click means, and each swallowing what the other was waiting for. Opening the bundle
    /// again normally never gets this far, because macOS hands that to the copy already running.
    ///
    /// The copy that is running is asked for its window, which is what opening the app again means, and this
    /// one leaves before it has created anything. **It is asked directly**, by a notification that copy
    /// listens for: opening the bundle instead hands the request to Launch Services and returns, and one made
    /// by a process on its way out was measured never to arrive.
    @MainActor private static func leaveIfAlreadyRunning() {
        let mine = ProcessInfo.processInfo.processIdentifier
        guard let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: AppIdentity.bundleIdentifier)
            .first(where: { $0.processIdentifier != mine && !$0.isTerminated })
        else { return }
        Log.app.error("already running as pid \(running.processIdentifier, privacy: .public); this copy leaves and asks it for its window")
        DistributedNotificationCenter.default().postNotificationName(
            AppDelegate.openedAgain, object: nil, userInfo: nil, deliverImmediately: true)
        exit(0)
    }
}
