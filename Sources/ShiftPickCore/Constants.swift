import Foundation

/// Every number the app is built on, once, with the evidence for it beside it. A number that is a matter of
/// taste is not here and is not offered as a setting either: it is a rule.
public enum K {
    // MARK: - Clicks

    /// How long the app gives Accessibility to answer one question. A tap's callback holds up the whole
    /// event stream while it runs, so a Finder that does not answer must be given up on rather than waited
    /// for. Measured on macOS 27: one `AXFrame` read of a Finder icon costs about 0.06 ms warm, so 200 ms
    /// is three thousand times the normal cost of the slowest single call the click path makes.
    public static let axTimeout: TimeInterval = 0.2

    /// The whole click path's budget. Past it the original event is returned unmodified, whatever has been
    /// worked out so far. Measured: reading every icon of a full screen costs 6 to 20 ms, so this is an
    /// order of magnitude of headroom and still far below the ~1 s at which the system takes a tap away.
    public static let clickBudget: TimeInterval = 0.15

    /// How long after a plain or ⌘ Command click the anchor is looked for. The click is returned to the
    /// system untouched first and this runs afterwards, so an ordinary click gains no latency at all; the
    /// wait is only there to let Finder finish selecting before it is asked what is under the pointer.
    public static let anchorDelay: TimeInterval = 0.06

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

    /// How often the onboarding window asks whether the permission has arrived. The one timer the app runs
    /// that is not answering something: it stops the moment the grant is there.
    public static let onboardingPollInterval: TimeInterval = 1
}
