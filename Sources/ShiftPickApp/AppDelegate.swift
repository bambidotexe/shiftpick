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
    private var onboarding: OnboardingWindowController?
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

        // Nothing here asks for the permission. The wizard's own button is the only thing in the app that
        // does, because a prompt nobody clicked for arrives with no explanation beside it and macOS remembers
        // a refusal for good.
        if Permissions.accessibilityGranted { engine.start() }

        // The wizard on a first run the person started, and on any launch that finds the permission missing,
        // however the app was launched: without it the app does nothing at all. A login item whose onboarding
        // was simply never finished still opens no window.
        if !Permissions.accessibilityGranted || (openedByHand && !store.settings.onboardingCompleted) {
            showOnboarding()
        } else if openedByHand {
            showSettings()
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
    /// `applicationDidFinishLaunching`. **The wizard takes precedence while it is up**, and this asks the same
    /// question a launch does, so a wizard that has not been walked is what opening the app brings up. A
    /// reinstall launches quietly and opens no window, so this is the first thing a person does afterwards,
    /// and it must not be the one path that skips the wizard. With no Dock icon, `open -b` is the only way the
    /// user fetches a window back. A login item cannot arrive here: it launches a process that is not running
    /// yet.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if onboarding?.isUp == true {
            onboarding?.show()
        } else if Permissions.accessibilityGranted && store.settings.onboardingCompleted {
            showSettings()
        } else {
            showOnboarding()
        }
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

    /// **A fresh controller every time**, so every row re-reads its state and the walk starts at page one.
    /// The one already on screen is brought forward instead, rather than replaced under the user.
    func showOnboarding() {
        if onboarding?.isUp == true {
            onboarding?.show()
            return
        }
        let controller = OnboardingWindowController.make(
            store: store,
            onFinish: { [weak self] in self?.store.settings.onboardingCompleted = true },
            grantMayHaveChanged: { [weak self] in self?.grantChanged() })
        controller.othersNeedUsActive = { [weak self] in
            self?.settingsWindow?.isUp == true || UpdateController.shared.windowIsUp
        }
        onboarding = controller
        controller.show()
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
    /// nothing happens, which is what "no polling while idle" means here. The wizard's own poll is the second
    /// way in, because this notification has been seen to arrive a moment before the process is really
    /// trusted; it calls the same method through `grantMayHaveChanged`.
    private func watchTheGrant() {
        trustObserver = DistributedNotificationCenter.default().addObserver(
            forName: Permissions.trustDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.grantChanged() }
        }
    }

    /// Called by the notification and by the wizard's poll, and safe to call when nothing has moved: each
    /// branch leaves at once if the engine is already where the grant says it should be.
    ///
    /// **The wizard is not closed when the grant arrives.** Its row ticks over to *Granted* and its button
    /// turns from *Skip* to *Continue*; closing it is the user's move. A window that vanished the moment the
    /// permission landed was a window nobody ever read.
    private func grantChanged() {
        if Permissions.accessibilityGranted {
            guard !engine.isWatching else { return }
            Log.app.notice("the Accessibility permission has arrived")
            engine.start()
        } else {
            guard engine.isWatching else { return }
            Log.app.error("the Accessibility permission has been taken away; back to onboarding")
            engine.stop()
            if onboarding?.isUp != true { showOnboarding() }
        }
    }

    // MARK: - Updates

    /// Last, so the launch that follows an Install and Relaunch finds the rest of the app in place when it
    /// opens the window that says how the install ended.
    private func startUpdates() {
        let updates = UpdateController.shared
        updates.onShowSettings = { [weak self] in
            guard let self else { return }
            if Permissions.accessibilityGranted { self.showSettings() } else { self.showOnboarding() }
        }
        updates.othersNeedUsActive = { [weak self] in
            self?.settingsWindow?.isUp == true || self?.onboarding?.isUp == true
        }
        updates.start()
    }
}
