import Foundation

/// The menu-bar menu. `MenuBarController` rebuilds it from scratch on every open and reads these then, so
/// the menu is never a language or a state behind.
public struct MenuStrings {
    private let language: Language
    init(_ language: Language) { self.language = language }

    public var launchAtLogin: String {
        switch language {
        case .en: "Launch at Login"
        case .fr: "Lancer à la connexion"
        }
    }

    public var settings: String {
        switch language {
        case .en: "Settings…"
        case .fr: "Réglages…"
        }
    }

    public var quit: String {
        switch language {
        case .en: "Quit \(AppIdentity.name)"
        case .fr: "Quitter \(AppIdentity.name)"
        }
    }

    /// The one read-only line: what the app is doing right now, and nothing else.
    public var statusWatching: String {
        switch language {
        case .en: "Watching for ⇧ Shift clicks"
        case .fr: "Surveille les clics avec ⇧ Majuscule"
        }
    }

    public var statusNeedsPermission: String {
        switch language {
        case .en: "Waiting for the Accessibility permission"
        case .fr: "En attente de la permission d'accessibilité"
        }
    }

    public var statusNoTap: String {
        switch language {
        case .en: "macOS refused the click listener"
        case .fr: "macOS a refusé l'écoute des clics"
        }
    }

    /// macOS took the click listener away `K.breakerTrips` times inside `K.breakerWindow`, and ShiftPick
    /// stopped creating it.
    public var statusStoppedByMacOS: String {
        switch language {
        case .en: "Stopped: macOS kept interrupting the click listener"
        case .fr: "Arrêté : macOS interrompait sans cesse l'écoute des clics"
        }
    }
}
