import AppKit
@preconcurrency import ApplicationServices
import Foundation

/// The one permission ShiftPick needs, and the only two things it does about it.
public enum Permissions {
    public static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system dialog that offers to open the Accessibility pane. Asked once, at a launch that
    /// finds the permission missing; the onboarding window says the same thing in more words and stays.
    public static func promptForAccessibility() {
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
