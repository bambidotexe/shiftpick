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
    private var sessionObservers: [(NotificationCenter, NSObjectProtocol)] = []
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
        // a refusal for good. Without it `start` creates nothing and says so.
        engine.start()

        // The wizard on a first run the person started, and on any launch that finds the permission missing,
        // however the app was launched: without it the app does nothing at all. A login item whose onboarding
        // was simply never finished still opens no window.
        if !Permissions.accessibilityGranted || (openedByHand && !store.settings.onboardingCompleted) {
            showOnboarding()
        } else if openedByHand {
            showSettings()
        }
        watchTheGrant()
        watchTheSession()
        startUpdates()
        Log.app.notice("\(AppIdentity.name, privacy: .public) \(AppIdentity.version, privacy: .public) launched")
    }

    /// Nothing to put back and nothing to flush: a tap dies with its process, and the kernel sees to that
    /// however the process ends. The taps are destroyed here all the same, first and explicitly, so that
    /// nothing a quit goes on to do can happen with one still in the event stream.
    func applicationWillTerminate(_ notification: Notification) {
        engine.shutDown()
    }

    /// **Before the uninstall resets the Accessibility grant.** An enabled click tap whose owner has just lost
    /// the grant stalls every click on the Mac, and an uninstall would otherwise be this app doing that to
    /// itself, a moment before it asks for a click on its last alert. Returns once no event tap exists, and
    /// nothing starts again after it: there is no way back from an uninstall that has been confirmed.
    ///
    /// An update needs none of this. Its helper touches nothing until this process has gone, and the quit
    /// that gets it there comes through `applicationWillTerminate`.
    func prepareForRemoval() {
        engine.shutDown()
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
    /// nothing happens, which is what "no polling while idle" means here.
    ///
    /// **The notification is a hint, never an answer, and nothing here reads the grant to decide what it
    /// meant.** It has been seen to arrive before `AXIsProcessTrusted()` changes, and a handler that read the
    /// old answer once and left is how a revoked grant went unnoticed under an enabled tap. So the engine is
    /// told every time: it disarms the click tap first, asks a live question, and looks again a few times
    /// over the next seconds. The wizard's own poll is the second way in, through `grantMayHaveChanged`.
    private func watchTheGrant() {
        trustObserver = DistributedNotificationCenter.default().addObserver(
            forName: Permissions.trustDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.engine.trustMayHaveChanged() }
        }
        // **The wizard comes back when the grant goes**, unless it is already up. Its row is then the one
        // place that says what happened and how to put it right.
        engine.$status
            .removeDuplicates()
            .scan((TapLifecycle.Status.stopped, TapLifecycle.Status.stopped)) { ($0.1, $1) }
            .sink { [weak self] before, now in
                guard before == .watching, now == .needsPermission else { return }
                Log.app.error("the Accessibility permission has been taken away; back to onboarding")
                if self?.onboarding?.isUp != true { self?.showOnboarding() }
            }
            .store(in: &cancellables)
    }

    /// Called by the wizard's poll, and safe to call when nothing has moved: the engine leaves at once if it
    /// is already where the grant says it should be.
    ///
    /// **The wizard is not closed when the grant arrives.** Its row ticks over to *Granted* and its button
    /// turns from *Skip* to *Continue*; closing it is the user's move. A window that vanished the moment the
    /// permission landed was a window nobody ever read.
    private func grantChanged() {
        engine.refreshTrust()
    }

    // MARK: - Sleep, the lock screen, another user's session

    /// Nothing is armed while nobody can be clicking: the Mac going to sleep, the screen locking, another
    /// user's session coming forward. Coming back asks about the grant again before anything arms, because
    /// a Mac that has been away is the one place a grant can have moved with no notification heard.
    private func watchTheSession() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let away: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.willSleepNotification),
            (workspace, NSWorkspace.sessionDidResignActiveNotification),
            (distributed, Notification.Name("com.apple.screenIsLocked")),
        ]
        let back: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.didWakeNotification),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification),
            (distributed, Notification.Name("com.apple.screenIsUnlocked")),
        ]
        for (center, name) in away {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.engine.suspend() }
            }
            sessionObservers.append((center, observer))
        }
        for (center, name) in back {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.engine.resume() }
            }
            sessionObservers.append((center, observer))
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
