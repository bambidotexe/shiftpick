import AppKit
@preconcurrency import ApplicationServices
import Foundation
import os
import ShiftPickCore

/// The one permission ShiftPick needs, and the only four things it does about it.
///
/// **The reader and the ask are two different calls, and they are never swapped.** `accessibilityGranted`
/// answers and shows nothing, which is why it may run behind a poll; `requestAccessibility` puts the
/// system's dialog on screen, and **only a control's action may call it**. A request API returns the current
/// state too, which makes it tempting as the reader, and behind a two second poll that is a permission
/// prompt every two seconds.
///
/// **And the reader is not the last word.** `accessibilityGranted` is an answer the system keeps for the
/// process: it is right at launch, it lags the notification that says the grant moved, and it has been seen
/// to go on saying yes after the grant was taken away. Windows may show it. **Nothing that enables an event
/// tap may rely on it alone**: that is what `liveVerdict` is for.
public enum Permissions {
    public static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system dialog that offers to open the Accessibility pane. **Called from a button and from
    /// nowhere else**, never from the app's start-up path: a prompt the user did not ask for arrives with no
    /// explanation beside it, and macOS remembers a refusal for good.
    ///
    /// The result is the state at the moment of the call, still not granted while the dialog is on screen, so
    /// nothing branches on it. The dialog carries its own button to the pane, so nothing opens one beside it.
    public static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @MainActor public static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// The notification the system posts when the privacy database changes. **It is a hint and not an
    /// answer**: it is posted for any application's grant, it has been seen to arrive before
    /// `accessibilityGranted` changes, and removing an application from the list with the minus button has
    /// been reported to post nothing at all. Whoever hears it disarms first and asks `liveVerdict` after.
    public static let trustDidChange = Notification.Name("com.apple.accessibility.api")

    // MARK: - The live question

    /// What one Accessibility call's result says about the grant. `apiDisabled` is the system refusing this
    /// process by name. An answer of any kind from the other side, including "that attribute has no value",
    /// is a request that was let through. Everything else, a timeout above all, says nothing either way.
    public static func verdict(for error: AXError) -> TrustVerdict {
        switch error {
        case .success, .noValue, .attributeUnsupported: .trusted
        case .apiDisabled: .revoked
        default: .unknown
        }
    }

    /// Asks another process a real Accessibility question and reports what came back. **Blocking, for up to
    /// `timeout`: never call it on the thread that serves the event taps.**
    ///
    /// The Dock is who is asked: it is always running, it is never the application the user is fighting
    /// with, and it answers one attribute in well under a millisecond. Finder is not, because a Finder stuck
    /// on a network volume would read as a grant nobody can vouch for.
    public static func liveVerdict(timeout: TimeInterval = K.trustProbeTimeout) -> TrustVerdict {
        guard AXIsProcessTrusted() else { return .revoked }
        guard let pid = witnessProcess() else { return .unknown }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Float(timeout))
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(application, kAXRoleAttribute as CFString, &value)
        let verdict = verdict(for: error)
        // The Dock restarts, and the pid kept from the one before would answer nothing for ever.
        if verdict == .unknown { witness.withLock { $0 = nil } }
        return verdict
    }

    private static let witnessBundleIdentifier = "com.apple.dock"
    private static let witness = OSAllocatedUnfairLock<pid_t?>(initialState: nil)

    private static func witnessProcess() -> pid_t? {
        if let pid = witness.withLock({ $0 }), kill(pid, 0) == 0 { return pid }
        let found = NSRunningApplication.runningApplications(withBundleIdentifier: witnessBundleIdentifier)
            .first?.processIdentifier
        witness.withLock { $0 = found }
        return found
    }
}
