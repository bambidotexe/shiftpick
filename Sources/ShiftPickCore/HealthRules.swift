import Foundation

/// The rules that turn what was found into a level. Every page that reports one of these states reads it
/// from here, so the System page's permission row and the Health page's agree.
public enum HealthRules {
    /// A macOS permission, or a setup the app asks for in its onboarding wizard: green while it is in
    /// place; missing, **red when the wizard marks it required** (the app cannot work without it) and orange
    /// otherwise (a feature that needs it cannot work, and the rest can). Never blue. A preference the wizard
    /// merely offers (Open at Login, Show in menu bar) is not a grant: off is the user's choice.
    public static func grant(held: Bool, required: Bool) -> HealthLevel {
        if held { return .good }
        return required ? .failure : .warning
    }

    /// Open at Login. Off is the user's choice and only worth knowing; switched off in System Settings while
    /// the app asked for it is a login that will not happen, which the user did not choose here.
    public static func loginItem(_ state: LoginItemState) -> HealthLevel {
        switch state {
        case .enabled: .good
        case .disabled: .info
        case .needsApproval: .warning
        }
    }

    /// A crash the app came back from still cost the user whatever it was doing, so any crash in the window
    /// is worth a look; none is green.
    public static func crashes(_ count: Int) -> HealthLevel {
        count == 0 ? .good : .warning
    }

    /// Running out of a disk image, or out of the read-only copy macOS makes of an app launched from where
    /// it was downloaded, is running an app that is not installed: it goes when the image is ejected, and an
    /// update cannot replace it. Any other folder is a choice.
    public static func location(_ location: AppLocation) -> HealthLevel {
        switch location {
        case .applications: .good
        case .elsewhere: .info
        case .diskImage, .temporaryCopy: .warning
        }
    }
}

// MARK: - ShiftPick's own

extension HealthRules {
    /// The click listener, as the engine reports it (`TapLifecycle.Status`). **It is the mechanism the whole
    /// app rests on**: while *Enable ShiftPick* is on, a listener macOS refused, or one the breaker stopped,
    /// is an app that does nothing at all, red. One waiting for the permission is blue: the permission's own
    /// row is the red one, and one cause counts once in the overview. Switched off by the user, it is the
    /// state they asked for, blue. Nil while nothing has been reported yet, before the first start and after
    /// the quit: no row.
    public static func listener(_ status: TapLifecycle.Status, userEnabled: Bool) -> HealthLevel? {
        if status == .stopped { return nil }
        guard userEnabled else { return .info }
        switch status {
        case .watching: return .good
        case .needsPermission: return .info
        case .refused, .breakerOpen, .stopped: return .failure
        }
    }

    /// Finder, whose icon views and Desktop are where almost every range is made. Not running, only the Open
    /// and Save panels shown as icons are left, so ShiftPick is degraded rather than stopped: orange.
    public static func finder(running: Bool) -> HealthLevel {
        running ? .good : .warning
    }
}

extension HealthRules {
    /// Whether a file in `~/Library/Logs/DiagnosticReports` is a crash report of the process named
    /// `process`: the name, a dash, the date the system stamps (`ShiftPick-2026-09-21-101010.ips`), and the
    /// extension of a crash report old or new. A user fault of the same process (`ExcUserFault_…`), or
    /// another process whose name merely starts the same way, is not.
    public static func isCrashReport(fileName: String, process: String) -> Bool {
        guard fileName.hasPrefix(process + "-"), fileName.hasSuffix(".ips") || fileName.hasSuffix(".crash")
        else { return false }
        let stamp = fileName.dropFirst(process.count + 1)
        // yyyy-MM-dd-HHmmss, digits where the date's digits go.
        let pattern = Array("0000-00-00-000000")
        guard stamp.count > pattern.count else { return false }
        return zip(stamp, pattern).allSatisfy { char, slot in slot == "-" ? char == "-" : char.isASCII && char.isNumber }
    }

    /// Where a bundle is, from its path. `home` is the user's home folder; `readOnlyVolume` is whether the
    /// volume the bundle is on is mounted read-only, which is what a disk image is.
    public static func location(bundlePath: String, home: String, readOnlyVolume: Bool) -> AppLocation {
        if bundlePath.contains("/AppTranslocation/") { return .temporaryCopy }
        if readOnlyVolume { return .diskImage }
        let folder = (bundlePath as NSString).deletingLastPathComponent
        if folder == "/Applications" || folder == (home as NSString).appendingPathComponent("Applications") {
            return .applications
        }
        return .elsewhere(folder: (folder as NSString).lastPathComponent)
    }
}

/// What `SMAppService` says about the app as a login item, in the app's own words.
public enum LoginItemState: Equatable, Sendable {
    case enabled
    /// Not registered: the switch is off, which is the user's to decide.
    case disabled
    /// Registered, then switched off in System Settings › General › Login Items & Extensions.
    case needsApproval
}

/// Where the running bundle is.
public enum AppLocation: Equatable, Sendable {
    /// `/Applications` or `~/Applications`.
    case applications
    /// A folder of the user's choosing, named by its last component.
    case elsewhere(folder: String)
    /// A read-only volume: the disk image it came in.
    case diskImage
    /// The randomised read-only copy macOS runs a quarantined app from (App Translocation).
    case temporaryCopy
}
