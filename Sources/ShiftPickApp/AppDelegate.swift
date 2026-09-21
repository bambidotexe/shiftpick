import AppKit
import Combine
import ShiftPickCore
import ShiftPickPlatform

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SettingsStore()
    private lazy var engine = ShiftPickEngine(store: store)
    private let menuBar = MenuBarController()

    private var settingsWindow: SettingsWindow?
    private var onboarding: OnboardingWindow?
    private var permissionTimer: Timer?
    private var trustObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Read before anything else can spend the event: `currentAppleEvent` is the launch's own, and only
        // until the first one the app handles itself. A reinstall opens the bundle as well, and the window
        // that got was one nobody asked for; the installer says so with a marker, which this reads once and
        // removes. An update writes that marker too, and says so a second way as well: while its outcome is
        // unread, this launch is the install helper's rather than a person's.
        let openedByHand = !launchedAsLoginItem() && !QuietLaunch.consume()
            && !UpdateController.shared.outcomeIsWaiting

        installMainMenu()
        menuBar.engine = engine
        menuBar.store = store
        menuBar.openSettings = { [weak self] in self?.showSettings() }
        menuBar.setup()

        if Permissions.accessibilityGranted {
            engine.start()
            if openedByHand { showSettings() }
        } else {
            Permissions.promptForAccessibility()
            showOnboarding()
        }
        watchTheGrant()
        startUpdates()
        Log.app.notice("\(AppIdentity.name, privacy: .public) \(AppIdentity.version, privacy: .public) launched")
    }

    /// Nothing to put back and nothing to flush: the tap dies with the process. Stopping it explicitly is
    /// only so that the log says when this app stopped listening.
    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    /// The one way back into Settings once the icon is hidden: opening the bundle again from the
    /// Applications folder or Spotlight while the app is already running fires this rather than
    /// `applicationDidFinishLaunching`. Onboarding takes precedence while the permission is missing, so a
    /// fresh install never shows two windows at once. A login item cannot arrive here: it launches a
    /// process that is not running yet.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if Permissions.accessibilityGranted { showSettings() } else { onboarding?.show() }
        return true
    }

    // MARK: - Windows

    /// Built on first use and kept: the window is cheap to hold, and re-showing the one the user closed
    /// keeps whatever page they were on.
    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(store: store, engine: engine,
                                            othersNeedUsActive: { [weak self] in
                                                self?.onboarding?.isUp == true
                                                    || UpdateController.shared.windowIsUp
                                            })
        }
        settingsWindow?.show()
    }

    private func showOnboarding() {
        if onboarding == nil { onboarding = OnboardingWindow() }
        onboarding?.show()
        startPermissionPoll()
    }

    /// An accessory application never shows a menu bar of its own, so nothing here is ever seen. It exists
    /// for its key equivalents alone: ⌘Q and ⌘W reach a window only through the main menu, and the Settings
    /// window, the onboarding window and the update window are all ordinary key windows.
    private func installMainMenu() {
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: Loc.menu.quit, action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: Loc.mainMenu.window)
        windowMenu.addItem(withTitle: Loc.mainMenu.close, action: #selector(NSWindow.performClose(_:)),
                           keyEquivalent: "w")
        windowMenu.addItem(withTitle: Loc.mainMenu.minimize, action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowItem.submenu = windowMenu

        let main = NSMenu()
        main.addItem(appItem)
        main.addItem(windowItem)
        NSApplication.shared.mainMenu = main
    }

    /// Whether macOS started the app as a login item rather than a person opening it.
    ///
    /// The open-application Apple event carries `keyAELaunchedAsLogInItem` under `keyAEPropData` when
    /// `SMAppService` is what launched us, and carries nothing there when the Finder, Spotlight or `open`
    /// did. The absent case therefore reads as opened by hand, which is the safe way round: an event this
    /// cannot recognise shows the Settings window rather than swallowing the one route back in when the
    /// menu-bar icon is hidden.
    private func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    // MARK: - The permission

    /// The grant given or taken away while the app runs, without a timer and without a relaunch: macOS
    /// posts a distributed notification whenever the privacy database changes. It costs nothing while
    /// nothing happens, which is what "no polling while idle" means here.
    private func watchTheGrant() {
        trustObserver = DistributedNotificationCenter.default().addObserver(
            forName: Permissions.trustDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.grantChanged() }
        }
    }

    private func grantChanged() {
        if Permissions.accessibilityGranted {
            guard !engine.isWatching else { return }
            Log.app.notice("the Accessibility permission has arrived")
            stopPermissionPoll()
            onboarding?.close()
            engine.start()
        } else {
            guard engine.isWatching else { return }
            Log.app.error("the Accessibility permission has been taken away; back to onboarding")
            engine.stop()
            showOnboarding()
        }
    }

    /// A second way in, for the case the notification does not cover: the database is written before the
    /// system decides this process is trusted, and the notification has been seen to arrive a moment early.
    /// It runs **only while the onboarding window is up** and stops on the first granted answer, which is
    /// the one timer this app ever arms that is not answering something.
    private func startPermissionPoll() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: K.onboardingPollInterval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Permissions.accessibilityGranted else { return }
                self.grantChanged()
            }
        }
    }

    private func stopPermissionPoll() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    // MARK: - Updates

    /// Last, so the launch that follows an Install and Relaunch finds the rest of the app in place when it
    /// opens the window that says how the install ended.
    private func startUpdates() {
        let updates = UpdateController.shared
        updates.onShowSettings = { [weak self] in
            guard let self else { return }
            if Permissions.accessibilityGranted { self.showSettings() } else { self.onboarding?.show() }
        }
        updates.othersNeedUsActive = { [weak self] in
            self?.settingsWindow?.isUp == true || self?.onboarding?.isUp == true
        }
        updates.start()
    }
}
