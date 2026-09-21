import AppKit
import ShiftPickCore
import ShiftPickPlatform
import SwiftUI

/// The app's settings, one page per subject, picked from the window's toolbar. Every page is a column of
/// groups built from the kit in `SettingsKit.swift`: a title, a card of rows, and under the card its hint,
/// its warnings and its notes.
///
/// Every control writes straight through `SettingsStore`, which persists on `didSet`, so there is no Apply
/// button and no local copy to get out of step.
struct SettingsView: View {
    @ObservedObject var selection: SettingsSelection
    @ObservedObject var store: SettingsStore
    @ObservedObject var status: SystemStatus
    @ObservedObject var engine: ShiftPickEngine

    var body: some View {
        // The page scrolls because the window's height is capped to what fits on the screen: on a short
        // display a long page is scrolled rather than cut off.
        ScrollView(.vertical) {
            page
                .frame(width: SettingsMetrics.contentWidth, alignment: .topLeading)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: SettingsPageHeight.self, value: proxy.size.height)
                    }
                }
        }
        .frame(width: SettingsMetrics.contentWidth)
        .onPreferenceChange(SettingsPageHeight.self) { [selection] height in
            // Preferences are delivered while SwiftUI updates, which is on the main actor.
            MainActor.assumeIsolated { selection.pageHeightChanged?(height) }
        }
    }

    @ViewBuilder private var page: some View {
        switch selection.page {
        case .general: GeneralPage(store: store, status: status, engine: engine)
        case .selection: SelectionPage(store: store)
        case .system: SystemPage(store: store, status: status, engine: engine)
        case .tip: TipPage()
        }
    }
}

/// The pages, in toolbar order. The raw value is the toolbar item's identifier, so the toolbar and the
/// selection cannot disagree about which page a click means.
///
/// General first, then the one feature, then what the app needs from the system, then the tip jar.
enum SettingsPageID: String, CaseIterable, Sendable {
    case general, selection, system, tip

    /// The toolbar item's label, and the window's title while the page is shown.
    var title: String {
        switch self {
        case .general: Loc.settings.pageGeneral
        case .selection: Loc.settings.pageSelection
        case .system: Loc.settings.pageSystem
        case .tip: Loc.settings.pageTip
        }
    }

    /// The SF Symbol drawn above the title, in the outline style the system's own settings toolbars use.
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .selection: "square.stack.3d.up"
        case .system: "checkmark.shield"
        case .tip: "mug"
        }
    }
}

/// What the window and its one SwiftUI root share: which page is shown, set by the toolbar, and where the
/// page's measured height goes, set by the window.
@MainActor
final class SettingsSelection: ObservableObject {
    @Published var page: SettingsPageID = .general
    /// Called with the shown page's natural height whenever it changes: on a page switch, and when a page
    /// gains or loses a line of its own.
    var pageHeightChanged: ((CGFloat) -> Void)?
}

/// How tall the shown page wants to be, read from behind the page.
struct SettingsPageHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - The system state the window shows

/// The two facts this window reports but does not own: whether Accessibility is granted, and whether
/// ShiftPick is registered as a login item. Both can change while the window is shut, and neither lives in
/// `Settings`.
///
/// **The window drives this, not a view.** `.onAppear` fires once per hosting view, and this window is
/// built once and re-shown, so a view-lifecycle hook would read the system exactly one time in the life of
/// the process. Nor is it a `TimelineView(.periodic:)`: nothing documents such a schedule stopping for a
/// window that is merely ordered out, and asking `AXIsProcessTrusted()` every two seconds for the life of
/// the process would run on the thread that serves the event tap.
///
/// Every property is published only when it actually changes, so an open window that is watching nothing
/// costs two reads every two seconds and no SwiftUI invalidation at all.
@MainActor
final class SystemStatus: ObservableObject {
    @Published private(set) var accessibilityGranted: Bool
    @Published private(set) var launchAtLogin: Bool

    private var timer: Timer?

    init() {
        accessibilityGranted = Permissions.accessibilityGranted
        launchAtLogin = LoginItem.isEnabled
    }

    func startPolling() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: K.systemPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        Log.app.debug("settings: system status poll started")
    }

    func stopPolling() {
        guard timer != nil else { return }
        timer?.invalidate()
        timer = nil
        Log.app.debug("settings: system status poll stopped")
    }

    /// Re-reads the login item alone, after an attempt to change it. Always read back rather than assumed:
    /// `register()` can fail, and a switch showing what the click asked for over a system that refused it
    /// is the worse of the two lies.
    func refreshLoginItem() {
        let enabled = LoginItem.isEnabled
        if enabled != launchAtLogin { launchAtLogin = enabled }
    }

    private func refresh() {
        let granted = Permissions.accessibilityGranted
        if granted != accessibilityGranted { accessibilityGranted = granted }
        refreshLoginItem()
    }
}
