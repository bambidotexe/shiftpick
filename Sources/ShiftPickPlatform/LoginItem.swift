import ServiceManagement

/// Launch at login. The state lives in `SMAppService` and nowhere else: the user can remove ShiftPick in
/// System Settings › General › Login Items without ever opening this app, so a copy of the answer kept in
/// the settings file could only ever disagree with the one that decides.
public enum LoginItem {
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    public enum Removal: Equatable, Sendable {
        case removed
        case failed(String)
        case noAnswer
    }

    /// Unregisters and waits for the service's answer, `timeout` at most. **Blocking: never on the main
    /// thread.**
    public static func remove(within timeout: TimeInterval) -> Removal {
        let reply = BoundedWait.answer(within: timeout) { (answer: @escaping @Sendable (String?) -> Void) in
            SMAppService.mainApp.unregister { error in answer(error?.localizedDescription) }
        }
        switch reply {
        case .none: return .noAnswer
        case .some(.none): return .removed
        case .some(.some(let reason)): return .failed(reason)
        }
    }
}
