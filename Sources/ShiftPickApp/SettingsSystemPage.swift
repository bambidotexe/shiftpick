import AppKit
import ShiftPickCore
import ShiftPickPlatform
import SwiftUI

/// What ShiftPick needs from macOS, and the controls that give it: the permission with its button, and the
/// way back to the wizard. The permission's row follows the system while the window is open, so granting it
/// in System Settings shows up here without closing it. Whether ShiftPick is actually watching for clicks is
/// a verdict with nothing to press beside it, and it is on the Health page.
struct SystemPage: View {
    @ObservedObject var status: SystemStatus
    @ObservedObject var engine: ShiftPickEngine

    var body: some View {
        let words = Loc.settings.system
        // The system's cached answer, except once ShiftPick has found the grant gone itself.
        let granted = engine.status.showsGrant(systemSays: status.accessibilityGranted)
        SettingsPage {
            // A state the user can fix is three things: the row; while it is red, a button to the place it
            // is fixed and a warning naming the exact switch; once green, the button and the warning go and
            // the row stays, so the link between the app and the permission stays visible. The row is also
            // on the Health page, in the same colour: the wizard marks the grant required, so it is red.
            SettingsGroup(title: words.accessibilityTitle,
                          hint: words.accessibilityHint,
                          warnings: granted ? [] : [words.accessibilityWarning],
                          notes: [words.accessibilityNote]) {
                StatusRow(words.accessibilityRow,
                          mark: StatusMark(HealthRules.grant(held: granted,
                                                             required: GrantCatalogue.accessibilityRequired),
                                           granted ? Loc.settings.words.granted : Loc.settings.words.denied))
                if !granted {
                    ButtonRow {
                        Button(words.openAccessibilityButton) { Permissions.openAccessibilitySettings() }
                    }
                }
            }

            // The wizard is the one place that explains the permission and the gesture together, so it stays
            // reachable after the first run. A fresh one is built each time, starting at page one.
            SettingsGroup(title: words.startOverTitle) {
                ButtonRow {
                    Button(words.showOnboardingButton) {
                        (NSApp.delegate as? AppDelegate)?.showOnboarding()
                    }
                }
            }
        }
    }
}
