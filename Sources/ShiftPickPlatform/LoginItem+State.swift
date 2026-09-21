import ServiceManagement
import ShiftPickCore

/// The login item as the Health page reports it. In a file of its own because `LoginItem.swift` is a file of
/// the safety layer (`scripts/safety-gates.sh`, for its bounded removal during an uninstall), and this is a
/// read and nothing else.
extension LoginItem {
    /// `isEnabled`'s answer with one more distinction: registered, then switched off in System Settings,
    /// which is a login that will not happen although the app asked for it. A reader: it registers nothing.
    public static var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .needsApproval
        default: .disabled
        }
    }
}
