import os
import ShiftPickCore

/// The app's logging surface, deliberately small: what is otherwise invisible, and nothing per event.
/// A chatty logger is one nobody reads, and this one sits on the thread that serves the event tap.
///
/// `/usr/bin/log show --predicate 'subsystem == "dev.rubens.ShiftPick"' --last 1h`
/// (`log` alone is a zsh builtin, hence the full path).
public enum Log {
    /// Launch, the permission, the settings window, the menu bar.
    public static let app = Logger(subsystem: AppIdentity.logSubsystem, category: "app")
    /// The click path: what it decided and why it let a click through. Nothing on the ordinary path, so a
    /// line here is always about a ⇧ Shift click.
    public static let click = Logger(subsystem: AppIdentity.logSubsystem, category: "click")
    /// Every check, what it found, the fetch, the unpacking and the hand-over to the install helper.
    public static let update = Logger(subsystem: AppIdentity.logSubsystem, category: "update")
    /// The onboarding wizard: the poll, the stepping button's word, and at `debug` where that button
    /// actually is. A button drawn in one place and hit-tested in another says nothing on its own, and this
    /// is the line that shows it (`docs/pitfalls.md` 11).
    public static let onboarding = Logger(subsystem: AppIdentity.logSubsystem, category: "onboarding")
}
