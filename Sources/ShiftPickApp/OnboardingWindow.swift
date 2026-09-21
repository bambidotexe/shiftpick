import AppKit
import ShiftPickCore
import ShiftPickPlatform
import SwiftUI

/// What a launch with no Accessibility permission shows, and which closes itself the moment the permission
/// arrives. It is the one window without which the app does nothing at all.
struct OnboardingView: View {
    /// The width the window is laid out for, before the padding around it.
    private static let width: CGFloat = 460
    private static let margin: CGFloat = 24

    var body: some View {
        let words = Loc.onboarding
        VStack(alignment: .leading, spacing: 16) {
            // `fixedSize` on every sentence, or a hosting controller sizing itself is free to propose a
            // width no window has and every one of them is drawn as a single truncated line. Measured: the
            // window came out 460 x 205 with three one-line texts in it.
            Text(words.heading)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(words.body)
                .fixedSize(horizontal: false, vertical: true)
            Text(words.steps)
                .fixedSize(horizontal: false, vertical: true)
            Button(words.openSettingsButton) { Permissions.openAccessibilitySettings() }
                .buttonStyle(.borderedProminent)
        }
        .frame(width: Self.width - Self.margin * 2, alignment: .leading)
        .padding(Self.margin)
    }
}

@MainActor
final class OnboardingWindow {
    private let window: NSWindow

    init() {
        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered,
                          defer: false)
        window.title = Loc.onboarding.windowTitle
        window.contentViewController = NSHostingController(rootView: OnboardingView())
        window.isReleasedWhenClosed = false
        window.center()
    }

    /// Whether the window is on screen. The Settings window asks, so that closing Settings over a still
    /// open onboarding window does not deactivate the app out from under it.
    var isUp: Bool { window.isVisible }

    func show() {
        // `ignoringOtherApps`, like the Settings window: measured on macOS 27, the cooperative `activate()`
        // cannot bring an accessory app forward. This is the window that most needs to be seen.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window.close() }
}
