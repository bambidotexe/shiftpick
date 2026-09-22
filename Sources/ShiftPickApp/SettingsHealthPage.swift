import ShiftPickCore
import ShiftPickPlatform
import SwiftUI

/// Whether ShiftPick works, at a glance: two tables and nothing else. **Health** holds the checks, each
/// green, orange or red, with Check Again under them and, while a line is orange or red, the sentence that
/// says where to put it right. **Information** holds a few readings, blue. The page reports and changes
/// nothing: a state is put right on the page that owns it.
///
/// What is a check, what is a reading, what goes on neither (a preference, the version, updates) and how
/// long each table may be are the `macos-building-settings-pages` skill's *The Health page*. The lines are
/// built in `HealthReport`, where they are tested; this view only draws them.
///
/// **The permission's line shows the grant through `TapLifecycle.Status.showsGrant`, like every window**:
/// macOS's cached answer was measured saying yes for seconds after the grant had gone, and once ShiftPick
/// has found it gone itself, that is what is shown. `SafetyNetTests` pins it. Nothing here asks anything of
/// the taps' thread: the listener's state is what the engine already published on the main actor.
struct HealthPage: View {
    @ObservedObject var status: SystemStatus
    @ObservedObject var engine: ShiftPickEngine
    @ObservedObject var health: HealthCheck

    var body: some View {
        let t = Loc.settings.health
        let granted = engine.status.showsGrant(systemSays: status.accessibilityGranted)
        let facts = health.facts(status, granted: granted, listener: engine.status)
        let checks = HealthReport.checks(for: facts)
        let readings = HealthReport.readings(for: facts)
        SettingsPage {
            SettingsGroup(title: t.healthTitle, warnings: checks.warnings) {
                ForEach(checks) { row in
                    StatusRow(row.label, mark: StatusMark(row.level, row.word)).help(row.detail ?? "")
                }
                ButtonRow {
                    if health.isChecking { ProgressView().controlSize(.small) }
                    Button(t.checkAgainButton) { health.checkAgain(status) }
                        .disabled(health.isChecking)
                }
            }

            if !readings.isEmpty {
                SettingsGroup(title: t.informationTitle) {
                    ForEach(readings) { row in
                        StatusRow(row.label, mark: .info(row.value)).help(row.detail ?? "")
                    }
                }
            }
        }
    }
}

extension StatusMark {
    /// The kit's mark for one of the Health table's three levels: green, orange, red. The System page's
    /// permission row takes its mark here too, so a state reads the same on both pages.
    init(_ level: HealthLevel, _ text: String) {
        switch level {
        case .good: self = .good(text)
        case .warning: self = .warning(text)
        case .failure: self = .failure(text)
        }
    }
}
