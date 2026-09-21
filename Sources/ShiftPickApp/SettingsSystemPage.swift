import ShiftPickCore
import ShiftPickPlatform
import SwiftUI

/// What ShiftPick needs from macOS, and whether it has it. Both rows follow the system while the window is
/// open, so granting the permission in System Settings shows up here without closing it.
struct SystemPage: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var status: SystemStatus
    @ObservedObject var engine: ShiftPickEngine

    var body: some View {
        let words = Loc.settings.system
        SettingsPage {
            // A state the user can fix is three things: the row; while it is red, a button to the place it
            // is fixed and a warning naming the exact switch; once green, the button and the warning go and
            // the row stays, so the link between the app and the permission stays visible.
            SettingsGroup(title: words.accessibilityTitle,
                          hint: words.accessibilityHint,
                          warnings: status.accessibilityGranted ? [] : [words.accessibilityWarning],
                          notes: [words.accessibilityNote]) {
                StatusRow(words.accessibilityRow,
                          mark: status.accessibilityGranted
                            ? .good(Loc.settings.words.granted)
                            : .failure(Loc.settings.words.denied))
                if !status.accessibilityGranted {
                    ButtonRow {
                        Button(words.openAccessibilityButton) { Permissions.openAccessibilitySettings() }
                    }
                }
            }

            // The one failure that is otherwise completely silent: the permission is granted, the app is
            // on, and macOS refused the tap anyway.
            SettingsGroup(title: words.clicksTitle,
                          hint: words.clicksHint,
                          warnings: clicksWarnings) {
                StatusRow(words.clicksRow, mark: clicksMark)
            }
        }
    }

    private var clicksMark: StatusMark {
        let vocabulary = Loc.settings.words
        // The colour follows whether the state is what it should be, not whether it is on: a user who has
        // turned ShiftPick off is looking at the state they asked for.
        if !store.settings.enabled { return .info(vocabulary.disabled) }
        return engine.isWatching ? .good(vocabulary.enabled) : .warning(vocabulary.disabled)
    }

    private var clicksWarnings: [String] {
        let words = Loc.settings.system
        if !store.settings.enabled { return [words.clicksWarningDisabled] }
        if engine.tapWasRefused || !engine.isWatching { return [words.clicksWarningNoTap] }
        return []
    }
}
