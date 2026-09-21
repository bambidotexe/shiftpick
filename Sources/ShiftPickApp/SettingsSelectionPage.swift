import ShiftPickCore
import ShiftPickPlatform
import SwiftUI

/// The one thing ShiftPick does, and the one choice about it. No setting restricts *where* it works: every
/// Finder icon view and the Desktop, in every Sort By mode, with or without groups.
struct SelectionPage: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        let words = Loc.settings.selection
        SettingsPage {
            SettingsGroup(title: words.shiftClickTitle,
                          hint: words.shiftClickHint,
                          notes: [words.shiftClickNote]) {
                ToggleRow(words.enableToggle, isOn: $store.settings.enabled)
                // A dependent switch, directly under its parent, in the same card, disabled with it.
                ToggleRow(words.commandShiftToggle, isOn: $store.settings.commandShiftAdds,
                          enabled: store.settings.enabled)
            }
        }
    }
}
