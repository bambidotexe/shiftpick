import ServiceManagement

/// Launch at login. The state lives in `SMAppService` and nowhere else: the user can remove ShiftPick in
/// System Settings › General › Login Items without ever opening this app, so a copy of the answer kept in
/// the settings file could only ever disagree with the one that decides.
public enum LoginItem {
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
