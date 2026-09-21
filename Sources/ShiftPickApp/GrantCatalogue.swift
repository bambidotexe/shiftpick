import AppKit
import ShiftPickCore
import ShiftPickPlatform

/// What a grant is, how the front is given back after one, and the two lists the onboarding wizard's pages
/// are made of. From `.claude/skills/building-onboarding/reference/GrantRow.swift`; read
/// `.claude/skills/building-onboarding/SKILL.md` before changing any of it.

// MARK: - What a grant is

/// Which row this is, whatever its title and its place in a list.
enum GrantID: String, CaseIterable, Sendable {
    case accessibility, openAtLogin, menuBarIcon
}

/// One grant the app depends on, or one thing the user may want set up: what the onboarding lists.
struct GrantItem {
    let id: GrantID
    /// **Exactly what System Settings calls this grant**, quoted from the system's own strings. The user has
    /// to find it in a list there, so a name of the app's own is a dead end however well it reads. A row
    /// with no switch in System Settings behind it carries the app's own name for it instead.
    let title: String
    /// One line: what the app can do with it. Not how it works.
    let why: String
    /// Whether the app cannot do its job without it. Drawn with a warning mark, and the page's button stays
    /// *Skip* until every required grant is there.
    let required: Bool
    /// Read live, every time. Never a cached copy: the user can grant and revoke behind the window.
    ///
    /// **A reader, never an ask.** `AXIsProcessTrusted()`, `SMAppService...status`, a stored setting. Never
    /// the call that requests: a request API returns the current state too, which makes it tempting here,
    /// and it also prompts. This closure runs on every poll tick, so that would be a permission prompt every
    /// two seconds.
    let granted: () -> Bool
    let buttonTitle: String
    /// Runs the flow; calls `done` on the main thread when the state may have changed. A flow that cannot
    /// finish in the app still calls `done`, at once.
    let action: (_ window: NSWindow?, _ done: @escaping () -> Void) -> Void

    /// Whether the flow puts up a dialog of the app's own and blocks until it is answered. macOS does not
    /// reactivate an accessory app when such a dialog closes, so a flow that owned one takes activation back
    /// when it ends.
    ///
    /// **A flow that hands over to System Settings or to a system permission prompt leaves this false.**
    /// Those report back immediately, while the thing they opened is still coming up, so taking activation
    /// then drops the window on top of the pane it has just opened.
    var returnsFocus: Bool = false

    /// The app this flow can send the user to, if any. **Every macOS permission sets this to System
    /// Settings**, not only the ones whose button opens a pane: the system's own dialog carries a button to
    /// System Settings, so any such row can be the reason the user ends up there. macOS gives an ordinary
    /// app the front back when the app it handed over to quits, and leaves an accessory app out of that, so
    /// the row waits for that app to quit and does it itself. Nil for a flow that stays inside this app.
    var mayOpen: String? = nil

    /// What the row shows once `granted()` is true.
    var doneTitle: String
    /// A row the app can undo itself: the button shown once `granted()` is true.
    var removeTitle: String? = nil
    var remove: ((_ window: NSWindow?, _ done: @escaping () -> Void) -> Void)? = nil
}

extension GrantItem {
    /// Activation back to `window` once a flow that owned a modal dialog has ended, and only then.
    @MainActor func reclaimFocusIfNeeded(_ window: NSWindow?) {
        guard returnsFocus, let window, window.isVisible else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Giving the front back

/// Gives the front back after the user has been sent to another app, the way macOS does for an ordinary app
/// by itself. One of these waits for a named app to quit and then brings its window forward, once.
///
/// macOS hands the front to whatever was in front before the app that quit, and skips `LSUIElement` apps
/// doing so. There is no flag for that. The alternative is becoming `.regular` for as long as the window is
/// up, which means a Dock icon and a main menu a menu-bar app has never had.
///
/// The wait is bounded: a user who dismisses the prompt and never goes to System Settings would otherwise
/// leave it armed, and an unrelated visit there much later would pull the window forward out of nowhere.
@MainActor
final class FocusReturnWatch {
    private var observer: NSObjectProtocol?
    private weak var target: NSWindow?

    deinit { if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }

    /// Waits for `bundleID` to quit, then brings `window` to the front. Replaces any earlier wait, and does
    /// nothing if the window has gone away or been closed by then.
    func whenQuit(_ bundleID: String, bringBack window: NSWindow?) {
        stop()
        guard let window else { return }
        target = window
        let deadline = Date().addingTimeInterval(K.focusReturnWait)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == bundleID
                else { return }
                let target = self.target
                self.stop()
                guard Date() < deadline, let target, target.isVisible else { return }
                NSApp.activate(ignoringOtherApps: true)
                target.makeKeyAndOrderFront(nil)
            }
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        target = nil
    }
}

// MARK: - The two lists

/// The rows of the wizard's two list pages.
///
/// **A row's action asks macOS and does nothing else.** The system's dialog carries its own way to the
/// Privacy and Security pane, so the app never opens a pane beside it, nor instead of it once the permission
/// has been refused. Nothing outside these actions ever calls a request API.
@MainActor
enum GrantCatalogue {
    /// The one permission, and it is required: without it the app does nothing at all.
    static var permissions: [GrantItem] {
        let words = Loc.onboarding
        return [
            GrantItem(id: .accessibility,
                      title: words.accessibilityTitle,
                      why: words.accessibilityWhy,
                      required: true,
                      granted: { Permissions.accessibilityGranted },
                      buttonTitle: words.allowButton,
                      action: { _, done in
                          Permissions.requestAccessibility()
                          done()
                      },
                      mayOpen: Self.systemSettings,
                      doneTitle: Loc.settings.words.granted),
        ]
    }

    /// Where the app lives: both optional, both undoable here, and neither is a permission. The login item
    /// is `SMAppService.mainApp`, which needs no dialog and opens no pane, so `mayOpen` stays nil.
    static func home(store: SettingsStore) -> [GrantItem] {
        let words = Loc.onboarding
        return [
            GrantItem(id: .openAtLogin,
                      title: words.openAtLoginTitle,
                      why: words.openAtLoginWhy,
                      required: false,
                      granted: { LoginItem.isEnabled },
                      buttonTitle: words.turnOnButton,
                      action: { window, done in Self.setLoginItem(true, window, done) },
                      doneTitle: Loc.settings.words.enabled,
                      removeTitle: words.turnOffButton,
                      remove: { window, done in Self.setLoginItem(false, window, done) }),
            GrantItem(id: .menuBarIcon,
                      title: Loc.settings.general.showInMenuBarToggle,
                      why: words.menuBarWhy,
                      required: false,
                      granted: { store.settings.showInMenuBar },
                      buttonTitle: words.turnOnButton,
                      action: { _, done in store.settings.showInMenuBar = true; done() },
                      doneTitle: Loc.settings.words.enabled,
                      removeTitle: words.turnOffButton,
                      remove: { _, done in store.settings.showInMenuBar = false; done() }),
        ]
    }

    /// The pane every permission row can send the user to, whether its own button does or the system's
    /// dialog offers to.
    private static let systemSettings = "com.apple.systempreferences"

    /// The state is `SMAppService`'s and is read back rather than assumed: `register()` can fail, and a row
    /// showing what the click asked for over a system that refused it is the worse of the two lies.
    private static func setLoginItem(_ enabled: Bool, _ window: NSWindow?, _ done: @escaping () -> Void) {
        do {
            try LoginItem.setEnabled(enabled)
        } catch {
            // Registering fails for an unsigned or un-bundled build. Said out loud rather than swallowed:
            // the row would otherwise simply stay as it was, with no reason given.
            let reason = Loc.settings.general.loginItemFailed(error.localizedDescription)
            Log.app.error("onboarding: the login item could not be changed: \(reason, privacy: .public)")
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = Loc.onboarding.openAtLoginTitle
            alert.informativeText = reason
            if let window { alert.beginSheetModal(for: window) { _ in } } else { alert.runModal() }
        }
        done()
    }
}
