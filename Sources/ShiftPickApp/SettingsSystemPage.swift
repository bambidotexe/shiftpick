import AppKit
import ShiftPickCore
import ShiftPickPlatform
import SwiftUI

/// What ShiftPick needs from macOS, and the controls that give it: the permission with its button, the click
/// listener with the button that starts it again, and the way back to the wizard. The permission's row
/// follows the system while the window is open, so granting it in System Settings shows up here without
/// closing it. The listener's row is here because the one thing that puts it right is here; it is on the
/// Health page as well, as a verdict, in the same colour and with the same word.
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

            // The click listener is what the whole app rests on, and the two ways it can be down are put
            // right in different places. **The warning follows the status**, so a red row is never silent:
            // a listener macOS refused says to quit and reopen, or to turn the switch above off and on; a
            // listener the breaker stopped says what happened and that the button below is the way back.
            // **The button belongs to the breaker alone**, because asking for another try is the only thing
            // it answers (docs/functional.md §1). The row stays once green so that the link between the app
            // and what it needs from macOS stays visible; no group at all while the permission is missing,
            // because the permission's own row says it.
            if let level = HealthRules.listener(engine.status) {
                let warning: String? = switch engine.status {
                case .breakerOpen: words.listenerStoppedWarning
                case .refused: Loc.settings.health.listenerRefusedFix
                case .watching, .needsPermission, .stopped: nil
                }
                SettingsGroup(title: words.listenerTitle, hint: words.listenerHint,
                              warnings: warning.map { [$0] } ?? []) {
                    StatusRow(Loc.settings.health.clicksRow,
                              mark: StatusMark(level, HealthReport.listenerWord(engine.status)))
                    if engine.breakerIsOpen {
                        ButtonRow { Button(words.startListeningButton) { engine.tryAgain() } }
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
