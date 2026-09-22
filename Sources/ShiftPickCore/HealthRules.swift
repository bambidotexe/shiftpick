import Foundation

/// The rules that turn what was found into a level. Every page that reports one of these states reads it
/// from here, so the System page's permission row and the Health page's agree.
public enum HealthRules {
    /// A macOS permission, or a setup the app asks for in its onboarding wizard: green while it is in
    /// place; missing, **red when the wizard marks it required** (the app cannot work without it) and orange
    /// otherwise (a feature that needs it cannot work, and the rest can). A preference the wizard merely
    /// offers (Open at Login, Show in menu bar) is not a grant, and never a line of the Health table.
    public static func grant(held: Bool, required: Bool) -> HealthLevel {
        if held { return .good }
        return required ? .failure : .warning
    }
}

// MARK: - ShiftPick's own

extension HealthRules {
    /// The click listener, as the engine reports it (`TapLifecycle.Status`). **It is the mechanism the whole
    /// app rests on**: a listener macOS refused, or one the breaker stopped, is an app that does nothing at
    /// all, red. Nil is no line at all, and it is two cases: waiting for the permission, which the
    /// permission's own line already says (one cause, one line); and nothing reported yet, before the first
    /// start and after the quit.
    public static func listener(_ status: TapLifecycle.Status) -> HealthLevel? {
        switch status {
        case .watching: return .good
        case .refused, .breakerOpen: return .failure
        case .needsPermission, .stopped: return nil
        }
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
}
