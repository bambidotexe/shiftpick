import AppKit
@preconcurrency import ApplicationServices
import Foundation

/// The one permission ShiftPick needs, and the only three things it does about it.
///
/// **The reader and the ask are two different calls, and they are never swapped.** `accessibilityGranted`
/// answers and shows nothing, which is why it may run behind a poll; `requestAccessibility` puts the
/// system's dialog on screen, and **only a control's action may call it**. A request API returns the current
/// state too, which makes it tempting as the reader, and behind a two second poll that is a permission
/// prompt every two seconds.
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

    /// The notification the system posts when the privacy database changes, which is how a grant given or
    /// taken away while the app runs reaches it without a timer. Observed on the distributed centre, so it
    /// costs nothing while nothing happens.
    public static let trustDidChange = Notification.Name("com.apple.accessibility.api")
}
