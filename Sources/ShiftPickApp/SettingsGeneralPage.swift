import AppKit
import ShiftPickCore
import ShiftPickPlatform
import SwiftUI

/// The app itself: its icon, where it starts, its version, the tip jar, and the two ways out.
struct GeneralPage: View {
    @ObservedObject var store: SettingsStore
    /// The login item's state lives in `SMAppService` alone, not in the settings file: the user can remove
    /// ShiftPick in System Settings › General › Login Items without ever opening this window. The switch
    /// therefore shows the system's answer, re-read on every open and on every poll.
    @ObservedObject var status: SystemStatus
    /// What the uninstall stops before it takes the grant away.
    let engine: ShiftPickEngine
    @State private var loginError: String?
    /// From the confirmation to the quit. The button is disabled meanwhile, so a second press cannot start a
    /// second uninstall behind the first.
    @State private var isUninstalling = false

    var body: some View {
        let words = Loc.settings.general
        SettingsPage {
            SettingsAppIcon()

            // There is no pause switch here: the Selection page has the one that matters. With the icon
            // hidden its menu is hidden with it, so the way back to this window has to be named.
            SettingsGroup(title: words.startupTitle, notes: [words.startupNote]) {
                ToggleRow(words.launchAtLoginToggle,
                          isOn: Binding(get: { status.launchAtLogin }, set: setLaunchAtLogin))
                ToggleRow(words.showInMenuBarToggle, isOn: $store.settings.showInMenuBar)
                if let loginError {
                    StatusRow(loginError, mark: .warning(Loc.settings.words.failed))
                }
            }

            UpdatesGroup()

            SettingsGroup(title: words.quitTitle) {
                // Through `NSApplication.terminate`, as the menu item does. No confirmation: opening the
                // app again undoes it.
                ButtonRow {
                    Button(words.quitButton, role: .destructive) { NSApp.terminate(nil) }
                }
            }

            // The warning is not a state that can be put right: it is the hazard of the other way out, and
            // the button beside it is the way that is not hazardous. It therefore always shows.
            SettingsGroup(title: words.uninstallTitle, hint: words.uninstallHint,
                          warnings: [words.uninstallWarning]) {
                ButtonRow {
                    Button(words.uninstallButton, role: .destructive) { confirmUninstall() }
                        .disabled(isUninstalling)
                }
            }
        }
    }

    /// Asks first, because it takes the app with it, and says afterwards what it could not remove.
    ///
    /// The preferences and the support folder are not removed here and cannot be: `cfprefsd` writes the
    /// domain out again as the process exits whatever happens. A detached helper waits for the pid instead.
    private func confirmUninstall() {
        let words = Loc.settings.general
        let alert = NSAlert()
        alert.messageText = words.uninstallConfirmTitle
        alert.informativeText = words.uninstallConfirmBody
        alert.alertStyle = .critical
        alert.addButton(withTitle: words.uninstallConfirmButton)
        alert.addButton(withTitle: words.uninstallCancelButton)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // **First, and before the grant is touched.** The steps below reset the Accessibility grant, and an
        // enabled click tap whose owner has just lost it stalls every click on the Mac, a moment before this
        // asks for one on its last alert. It returns once no tap exists. There is no way back from here, so
        // nothing starts again.
        engine.shutDown()
        // Nothing of the window's own reads the grant or the login item while they are being taken away.
        status.stopPolling()
        isUninstalling = true

        // **Off the main thread.** Every step waits on another process, each within `K.uninstallStepWait`, so
        // the window stays responsive however long macOS takes, and a step that never answers is named in the
        // last alert instead of freezing the app (`docs/pitfalls.md` 16).
        DispatchQueue.global(qos: .userInitiated).async {
            let failures = Uninstall.removeSystemRegistrations()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { finishUninstall(after: failures) }
            }
        }
    }

    /// The bundle to the Trash, the helper that removes the rest once this process has gone, and the last
    /// alert, which names whatever could not be done. Then the app quits.
    private func finishUninstall(after registrations: [UninstallFailure]) {
        let words = Loc.settings.general
        var failures = registrations
        Uninstall.moveBundleToTrash { failure in
            if let failure { failures.append(failure) }
            if let failure = Uninstall.startHelper() { failures.append(failure) }
            let result = NSAlert()
            result.messageText = failures.isEmpty ? words.uninstallDoneTitle : words.uninstallPartialTitle
            result.informativeText = failures.isEmpty
                ? words.uninstallDoneBody
                : failures.map(Self.sentence).joined(separator: "\n\n")
            result.alertStyle = failures.isEmpty ? .informational : .warning
            result.addButton(withTitle: words.uninstallQuitButton)
            result.runModal()
            NSApp.terminate(nil)
        }
    }

    /// `Uninstall` says which step and what the system said; the words are this page's.
    private static func sentence(for failure: UninstallFailure) -> String {
        let words = Loc.settings.general
        switch failure.step {
        case .accessibilityGrant: return words.uninstallGrantFailed
        case .loginItem: return words.uninstallLoginItemFailed(failure.reason)
        case .bundleToTrash: return words.uninstallTrashFailed(failure.reason)
        case .storedState: return words.uninstallHelperFailed(failure.reason)
        case .storedStateNotProvablyOurs: return words.uninstallHelperFailed(words.uninstallRefusedReason)
        case .loginItemNoAnswer: return words.uninstallLoginItemFailed(words.uninstallNoAnswerReason)
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            try LoginItem.setEnabled(on)
            loginError = nil
        } catch {
            // Registering fails for an unsigned or un-bundled build; the message is shown rather than
            // swallowed, and the switch settles wherever the system actually ended up.
            loginError = Loc.settings.general.loginItemFailed(error.localizedDescription)
        }
        status.refreshLoginItem()
    }
}

// MARK: - Updates

/// The version row carries the last answer as its mark, and the group has one button: the way to look for a
/// release, or, once a newer one is known, the way to get it, which opens the update window. The app also
/// looks on its own, shortly after launch and then weekly, so the state is the app's
/// (`UpdateController.shared`) and not this view's: what a check found while the window was closed is here
/// when it opens.
private struct UpdatesGroup: View {
    @ObservedObject private var updates = UpdateController.shared

    var body: some View {
        let words = Loc.settings.general
        SettingsGroup(title: words.updatesTitle) {
            // The app's own name is never translated, so the version row is built rather than looked up.
            StatusRow(updates.appVersion.isEmpty
                        ? AppIdentity.name : "\(AppIdentity.name) \(updates.appVersion)",
                      mark: mark)
            ButtonRow {
                if updates.panel.offersUpdate {
                    Button(words.updateButton) { updates.press() }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                } else {
                    Button(words.checkForUpdatesButton) { updates.press() }
                        .disabled(updates.panel.isBusy)
                }
            }
        }
    }

    /// What the version row says on its right, or nothing before the first answer.
    private var mark: StatusMark? {
        let words = Loc.settings.general
        switch updates.panel.state {
        case .idle: return nil
        case .checking: return .busy(words.checking)
        case .upToDate: return .good(words.upToDate)
        case .available(let version): return .info(words.versionAvailable(version.displayString))
        case .noRelease: return .warning(words.noReleaseYet)
        case .checkFailed(let reason): return .warning(words.couldNotCheck(reason))
        case .installFailed(let reason): return .warning(words.updateFailed(reason))
        }
    }
}
