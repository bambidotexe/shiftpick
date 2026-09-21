import Foundation

/// Every number the app is built on, once, with the evidence for it beside it. A number that is a matter of
/// taste is not here and is not offered as a setting either: it is a rule.
public enum K {
    // MARK: - Clicks

    /// How long the app gives Accessibility to answer one question. It sits **under `clickBudget`**, so one
    /// call that never answers cannot spend the whole budget on its own and the worker is free again soon
    /// after the click has been given up on. Measured on macOS 27: one `AXFrame` read of a Finder icon costs
    /// about 0.06 ms warm, so 100 ms is fifteen hundred times the normal cost of the slowest single call the
    /// click path makes.
    public static let axTimeout: TimeInterval = 0.1

    /// The whole click path's budget, **enforced by the wait and not by the work**: the tap's thread hands
    /// the click to the worker and waits this long for an answer, and past it the original event is returned
    /// unmodified whatever the worker is still doing. Measured: reading every icon of a full screen costs 6
    /// to 20 ms, so this is an order of magnitude of headroom and still far below the ~1 s at which the
    /// system takes a tap away.
    public static let clickBudget: TimeInterval = 0.15

    /// How much longer a click is held when the budget runs out **while the selection is already being
    /// set**. Letting the click through at that instant would have Finder toggle the clicked file on top of
    /// the range, so the one call in flight is waited for, and for no longer than `axTimeout` lets it take.
    public static let commitGrace: TimeInterval = 0.1

    // MARK: - The click tap's lifecycle

    /// How long a live answer about the grant stays good enough to arm on. Taking the grant away means
    /// finding the switch in System Settings and flipping it, which no hand does within two seconds of a
    /// ⇧ Shift press that was answered; and it keeps a burst of capital letters from asking the Dock the same
    /// question at every one of them.
    public static let trustFreshness: TimeInterval = 2

    /// How long the live question is given. It is asked of the Dock, which answers one attribute in well
    /// under a millisecond; past this the answer is `unknown` and nothing is armed.
    public static let trustProbeTimeout: TimeInterval = 0.05

    /// How often the armed state is looked at, **and only while it is armed**: is ⇧ Shift still down, is the
    /// grant still there, has anything been clicked. Most ⇧ Shift clicks are over before the first tick.
    public static let armedWatchInterval: TimeInterval = 0.5

    /// How long the click tap stays armed with nothing clicked. A ⇧ Shift key held down by a bag or latched
    /// by Sticky Keys would otherwise keep the one dangerous object in the app enabled for hours; the next
    /// press of the key arms it again.
    public static let armedIdleLimit: TimeInterval = 60

    /// How many times macOS may take the click tap away inside `breakerWindow` before ShiftPick stops
    /// creating it. Measured, the day the grant was revoked under a tap that re-enabled itself: three
    /// timeouts in thirteen seconds, every one of them a click that stalled the whole Mac. Each trip costs
    /// the user one stalled click, so three is the most this app will ever spend before it turns itself off
    /// and says so.
    public static let breakerTrips = 3
    public static let breakerWindow: TimeInterval = 60

    /// When the grant is asked about again after the system says the privacy database moved. The
    /// notification has been seen to arrive before the answer changes, so one look is not enough; three,
    /// spread over three seconds, and then nothing: this is a burst after an event, never a poll.
    public static let trustRecheckDelays: [TimeInterval] = [0.25, 1, 3]

    /// How often ⇧ Shift heard while the Mac is said to be away makes the session be looked at again. Once is
    /// what a lost wake or unlock notification needs, and it is the first press of the key; the rest is a
    /// password being typed on the lock screen, which is not a reason to ask at every capital letter.
    public static let awayCheckInterval: TimeInterval = 5

    /// How long tearing the taps down waits for the tap's own thread before doing it from the calling
    /// thread instead. That thread only ever waits `clickBudget + commitGrace`, so twice that is already a
    /// thread that is not coming back.
    public static let shutDownWait: TimeInterval = 0.5

    /// How long after a plain or ⌘ Command click the anchor is looked for. The click is returned to the
    /// system untouched first and this runs afterwards, so an ordinary click gains no latency at all; the
    /// wait is only there to let Finder finish selecting before it is asked what is under the pointer.
    public static let anchorDelay: TimeInterval = 0.06

    // MARK: - Uninstalling

    /// How long one step of the uninstall waits for the process or the daemon it depends on. `tccutil`
    /// resets the grant in about ten milliseconds and the login item answers in well under a second, so ten
    /// seconds is a step that is not coming back: it is reported failed, named in the last alert, and the
    /// uninstall goes on without it.
    public static let uninstallStepWait: TimeInterval = 10

    // MARK: - Updates

    /// How long after launch the first check nobody asked for is made. Late enough that it never competes
    /// with the launch itself.
    public static let updateLaunchDelay: TimeInterval = 20

    /// How often the schedule is looked at. Coarse on purpose: the app holds one repeating timer and asks
    /// at every wake as well, so a Mac that slept through the date is asked as soon as it is awake.
    public static let updateTick: TimeInterval = 60 * 30

    /// A week between two checks that got an answer, whoever asked.
    public static let updateInterval: TimeInterval = 7 * 24 * 60 * 60

    /// A check that could not reach GitHub is tried again at the first tick an hour or more later.
    public static let updateRetryDelay: TimeInterval = 60 * 60

    public static let updateCheckTimeout: TimeInterval = 15

    /// How long the app waits for its own quit after Install and Relaunch before it stops the helper and
    /// says so. Shorter than the helper's own `updateQuitWait`, so the helper's limit only ever serves an
    /// app too hung to stop it.
    public static let updateStallNotice: TimeInterval = 8

    /// Seconds the helper waits for the app to quit, for the new version to show among the running
    /// processes, and how long after that it looks once more.
    public static let updateQuitWait = 30
    public static let updateLaunchWait = 20
    public static let updateSettle = 3

    /// Past this, an install result was left behind by an install nobody is waiting on any more, and it
    /// opens no window.
    public static let updateResultShelfLife: TimeInterval = 10 * 60

    // MARK: - Windows

    /// How often the Settings window re-reads what it does not own — the permission, the login item.
    /// Slow enough to be free, fast enough that flipping a switch in System Settings and coming back finds
    /// the page already right. Started and stopped by the window, never by a view's `onAppear`.
    public static let systemPollInterval: TimeInterval = 2

    /// How often the onboarding wizard re-reads the rows on its page, and tells the app that the permission
    /// may have arrived. Slow enough to be free, fast enough that granting in System Settings and coming
    /// back finds the row already right. **The app's only poll**: the wizard starts it when it opens and
    /// stops it when it closes, and nothing else watches the permission on a timer.
    public static let onboardingPollInterval: TimeInterval = 2

    /// How long a wait for another app to quit stays honoured, after a row's button has sent the user to
    /// System Settings. Long enough to grant a permission, short enough that an unrelated visit there much
    /// later does not pull the wizard forward out of nowhere.
    public static let focusReturnWait: TimeInterval = 300
}
