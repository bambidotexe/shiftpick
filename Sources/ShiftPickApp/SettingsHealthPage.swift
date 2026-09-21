import AppKit
import ShiftPickCore
import ShiftPickPlatform
import SwiftUI

/// Whether ShiftPick is doing its job, at a glance: one overview row that sums the page up, then every state
/// that bears on it, grouped by subject, each a `StatusRow` in the colour of its level. It reports and
/// changes nothing: a state is put right on the page that owns it, and each orange or red row says where in
/// a warning under its group.
///
/// What goes here, what does not (the version and updates stay on General), and which colour a state takes
/// are the `macos-building-settings-pages` skill's *The Health page*. The rows themselves are built in
/// `HealthReport`, where they are tested; this view only draws them.
///
/// **The permission's row shows the grant through `TapLifecycle.Status.showsGrant`, like every window**:
/// macOS's cached answer was measured saying yes for seconds after the grant had gone, and once ShiftPick
/// has found it gone itself, that is what is shown. `SafetyNetTests` pins it. Nothing here asks anything of
/// the taps' thread: the listener's state is what the engine already published on the main actor.
struct HealthPage: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var status: SystemStatus
    @ObservedObject var engine: ShiftPickEngine
    @ObservedObject var health: HealthCheck

    var body: some View {
        let t = Loc.settings.health
        let granted = engine.status.showsGrant(systemSays: status.accessibilityGranted)
        let groups = HealthReport.groups(for: health.facts(status, granted: granted, listener: engine.status,
                                                           userEnabled: store.settings.enabled))
        let summary = HealthSummary(groups: groups)
        SettingsPage {
            SettingsGroup(title: t.overviewTitle) {
                StatusRow(AppIdentity.name,
                          mark: health.isChecking
                            ? .busy(t.checking)
                            : StatusMark(summary.level, HealthReport.summaryWord(summary)))
                ButtonRow {
                    Button(t.checkAgainButton) { health.checkAgain(status) }
                        .disabled(health.isChecking)
                }
            }

            ForEach(groups) { group in
                SettingsGroup(title: group.title, hint: group.hint, warnings: group.warnings) {
                    ForEach(group.rows) { row in
                        HealthRowView(row: row)
                    }
                }
            }

            SettingsGroup(title: t.reportTitle, hint: t.reportHint) {
                ButtonRow {
                    Button(t.copyReportButton) { copyReport(groups) }
                }
            }
        }
    }

    private func copyReport(_ groups: [HealthGroup]) {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let text = HealthReport.text(appName: AppIdentity.name, version: AppIdentity.version,
                                     system: "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                                     groups: groups)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// One row of the page: the kit's `StatusRow`, and what only a bug report needs as its tooltip.
private struct HealthRowView: View {
    let row: HealthRow

    var body: some View {
        if let detail = row.detail, !detail.isEmpty {
            StatusRow(row.label, mark: StatusMark(row.level, row.word)).help(detail)
        } else {
            StatusRow(row.label, mark: StatusMark(row.level, row.word))
        }
    }
}

extension StatusMark {
    /// The kit's mark for one of the Health page's four levels: blue, green, orange, red. The System page's
    /// permission row takes its mark here too, so a state reads the same on both pages.
    init(_ level: HealthLevel, _ text: String) {
        switch level {
        case .info: self = .info(text)
        case .good: self = .good(text)
        case .warning: self = .warning(text)
        case .failure: self = .failure(text)
        }
    }
}
