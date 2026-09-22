import AppKit
import Combine
import CoreGraphics
import Foundation
import ShiftPickCore
import ShiftPickPlatform

/// The feature, as the rest of the app sees it: start it, stop it, and what state it is in.
///
/// It owns three things and does none of their work. `ClickGuard` holds the two event taps on a thread of
/// their own; `ShiftClickResolver` makes every Accessibility call on a worker queue; `DeadlineGate` is the
/// only way a held click gets from the first to the second, and it keeps the click's budget whatever the
/// worker does. **The main thread is in none of it**: a window that stalls, an alert that runs, a `tccutil`
/// that is waited for, none of them can delay a click.
///
/// What is left here is wiring, and the one published fact the windows and the menu draw: `status`.
@MainActor
final class ShiftPickEngine: ObservableObject {
    /// What the click listener is doing, as `TapLifecycle` reports it. Arming and disarming are not in it:
    /// they happen at every capital letter.
    @Published private(set) var status: TapLifecycle.Status = .stopped

    /// Whether the taps exist and ⇧ Shift is being listened for.
    var isWatching: Bool { status == .watching }
    /// The permission reads as granted and macOS would still not create the taps. It is the one failure
    /// that is otherwise completely silent.
    var tapWasRefused: Bool { status == .refused }
    /// macOS kept taking the click tap away, and ShiftPick stopped creating it.
    var breakerIsOpen: Bool { status == .breakerOpen }

    /// ⇧ Shift was pressed while the Mac is said to be away. Whoever keeps count of why it is away looks at
    /// the session again, and calls `resume` if nothing is.
    var onShiftHeardWhileAway: (() -> Void)?

    private let store: SettingsStore
    private let resolver = ShiftClickResolver()
    private let clickGuard: ClickGuard

    init(store: SettingsStore) {
        self.store = store
        let resolver = self.resolver
        let gate = DeadlineGate(queue: resolver.queue)
        let status = StatusRelay()

        clickGuard = ClickGuard(hooks: ClickGuard.Hooks(
            decidePress: { point, flags in
                let outcome = gate.run(budget: K.clickBudget, grace: K.commitGrace) { ticket in
                    resolver.shiftClick(at: point, flags: flags, ticket: ticket)
                }
                switch outcome {
                case .answered:
                    break
                case .busy:
                    Log.click.error("let through: the worker is still busy with an earlier click")
                case .outOfTime:
                    Log.click.error("let through: no answer in \(K.clickBudget, privacy: .public) s")
                case .outOfTimeWhileSelecting:
                    Log.click.error("let through while the selection was being set: Finder will have toggled the clicked file on top of it")
                }
                return outcome.swallow
            },
            plainClick: { point in resolver.notePlainClick(at: point) },
            probeTrust: { answer in resolver.queue.async { answer(Permissions.liveVerdict()) } },
            statusChanged: { new in DispatchQueue.main.async { status.deliver(new) } },
            checkStillAway: { DispatchQueue.main.async { status.stillAway() } }))

        status.deliver = { [weak self] new in
            MainActor.assumeIsolated { self?.statusChanged(to: new) }
        }
        status.stillAway = { [weak self] in
            MainActor.assumeIsolated { self?.onShiftHeardWhileAway?() }
        }
        resolver.onGrantLost = { [weak clickGuard] in clickGuard?.trustWasLost() }
    }

    // MARK: - Running

    /// Launch, or the grant arriving. Asking twice is asking once, and it never closes an open breaker:
    /// the System page's button is what does.
    func start() {
        resolver.forgetAnchor()
        clickGuard.start()
    }

    /// The System page's button, once the breaker has opened: the only thing that closes it, and it still
    /// asks the live question about the grant before anything is created.
    func tryAgain() { clickGuard.tryAgain() }

    /// **Returns once no event tap exists.** It comes before anything that takes the grant, the bundle or
    /// the process away, and nothing starts again after it.
    func shutDown() {
        if clickGuard.shutDown() {
            Log.app.notice("stopped listening; no event tap exists")
        } else {
            Log.app.error("stopped listening; the taps' own thread did not answer, so they were destroyed from the main thread")
        }
    }

    /// The Mac is going to sleep, the screen is locking, or another user's session is coming forward.
    func suspend() { clickGuard.suspend() }

    func resume() {
        resolver.forgetAnchor()
        clickGuard.resume()
    }

    /// The system said the privacy database moved, which may or may not be about this app. The click tap is
    /// disarmed first and the grant is asked about afterwards, a few times over a few seconds.
    func trustMayHaveChanged() { clickGuard.trustMayHaveChanged() }

    /// A cheap look, for a poll that is running anyway: the onboarding wizard's. It asks for a start when the
    /// grant reads as given, which after a loss creates nothing until a live answer agrees, and takes the
    /// listener down when the grant reads as gone.
    func refreshTrust() {
        if Permissions.accessibilityGranted { clickGuard.start() } else { clickGuard.trustWasLost() }
    }

    private func statusChanged(to new: TapLifecycle.Status) {
        guard new != status else { return }
        status = new
        switch new {
        case .watching: Log.app.notice("listening for ⇧ Shift clicks")
        case .needsPermission: Log.app.notice("not listening: the Accessibility permission is missing")
        case .refused: Log.app.error("not listening: macOS would not create the event taps")
        case .breakerOpen: Log.app.error("not listening: macOS kept taking the click tap away, so it is no longer created")
        case .stopped: break
        }
    }
}

/// How what the taps' thread reports reaches an object that belongs to the main actor, without that object
/// being captured before it exists.
private final class StatusRelay: @unchecked Sendable {
    var deliver: (TapLifecycle.Status) -> Void = { _ in }
    var stillAway: () -> Void = {}
}
