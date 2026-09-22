import Foundation
import ShiftPickCore
import ShiftPickPlatform

/// The readings only the Health page shows: whether Finder is running, how long the app has been up, what
/// it holds and its crashes. What the rest of the window also shows (the permission) is `SystemStatus`'s,
/// polled every 2 s while the window is open, and what the click listener is doing is the engine's published
/// status; these are read when the page is shown and when Check Again is pressed, and never on a timer, so a
/// page nobody is looking at costs nothing.
///
/// **The window drives this, not a view**, like `SystemStatus`: `SettingsWindow` reads it when it opens on
/// the Health page and when the page is picked.
///
/// **Nothing here asks anything that can block, and nothing here asks for anything.** Every reading is the
/// process's own record, the workspace's list of running apps, or a folder of the user's; none is an
/// Accessibility call, none waits on another process, and none is a request API. Each answers at once, so
/// all of them are read on the main thread.
@MainActor
final class HealthCheck: ObservableObject {
    struct Readings: Equatable {
        var finderRunning: Bool?
        var runningSeconds: TimeInterval?
        var memoryBytes: UInt64?
        var recentCrashes: [Date] = []
    }

    @Published private(set) var readings = Readings()
    /// True from a press of Check Again until its readings have landed, and for at least
    /// `K.healthMinimumBusy`.
    @Published private(set) var isChecking = false

    /// Everything the page reports: the polled grant from `status`, the grant as the page shows it
    /// (`granted`, which the page gets through `TapLifecycle.Status.showsGrant`), the listener as the engine
    /// last reported it, and the rest from here.
    func facts(_ status: SystemStatus, granted: Bool, listener: TapLifecycle.Status) -> HealthFacts {
        HealthFacts(accessibilityGranted: granted, accessibilitySystemSays: status.accessibilityGranted,
                    accessibilityRequired: GrantCatalogue.accessibilityRequired,
                    listener: listener, finderRunning: readings.finderRunning,
                    runningSeconds: readings.runningSeconds, memoryBytes: readings.memoryBytes,
                    recentCrashes: readings.recentCrashes)
    }

    /// Reads everything again. Cheap: the list of running apps, a sysctl, a task_info and a directory listing.
    func read() {
        let now = Date()
        let process = Bundle.main.executableURL?.lastPathComponent ?? AppIdentity.name
        let fresh = Readings(
            finderRunning: FinderProcess.isRunning,
            runningSeconds: ProcessStats.launchDate.map { now.timeIntervalSince($0) },
            memoryBytes: ProcessStats.memoryFootprint,
            recentCrashes: CrashReports.recent(process: process, since: now.addingTimeInterval(-K.healthCrashWindow)))
        if fresh != readings { readings = fresh }
    }

    /// Check Again: every reading now, the polled states with them, and a spinner beside the button long
    /// enough to be seen. It changes nothing: the engine is not asked to start, stop or try again. The polled
    /// states are left alone while the poll is paused, which is what an uninstall does while it takes the
    /// grant and the login item away.
    func checkAgain(_ status: SystemStatus) {
        guard !isChecking else { return }
        isChecking = true
        if status.isPolling { status.refresh() }
        read()
        DispatchQueue.main.asyncAfter(deadline: .now() + K.healthMinimumBusy) { [weak self] in
            self?.isChecking = false
        }
    }
}
