import Foundation

/// The General page: Startup, Updates, Quit, Uninstall.
public struct GeneralPageStrings {
    private let language: Language
    init(_ language: Language) { self.language = language }

    // MARK: Startup

    public var startupTitle: String {
        switch language {
        case .en: "Startup"
        case .fr: "Démarrage"
        }
    }

    public var startupNote: String {
        switch language {
        case .en: "With the icon hidden, \(AppIdentity.name) keeps working. Open it again from the "
            + "Applications folder or Spotlight to get back to this window."
        case .fr: "Avec l'icône masquée, \(AppIdentity.name) continue de fonctionner. Rouvrez-le "
            + "depuis le dossier Applications ou Spotlight pour revenir à cette fenêtre."
        }
    }

    public var launchAtLoginToggle: String {
        switch language {
        case .en: "Launch at login"
        case .fr: "Lancer à la connexion"
        }
    }

    public var showInMenuBarToggle: String {
        switch language {
        case .en: "Show in menu bar"
        case .fr: "Afficher dans la barre des menus"
        }
    }

    public func loginItemFailed(_ reason: String) -> String {
        switch language {
        case .en: "Launch at login could not be changed: \(reason)"
        case .fr: "Le lancement à la connexion n'a pas pu être modifié : \(reason)"
        }
    }

    // MARK: Updates

    public var updatesTitle: String {
        switch language {
        case .en: "Updates"
        case .fr: "Mises à jour"
        }
    }

    public var checking: String {
        switch language {
        case .en: "Checking"
        case .fr: "Vérification"
        }
    }

    public var upToDate: String {
        switch language {
        case .en: "Up to date"
        case .fr: "À jour"
        }
    }

    public func versionAvailable(_ version: String) -> String {
        switch language {
        case .en: "Version \(version) is available"
        case .fr: "La version \(version) est disponible"
        }
    }

    public var noReleaseYet: String {
        switch language {
        case .en: "No release published yet"
        case .fr: "Aucune version publiée pour l'instant"
        }
    }

    public func couldNotCheck(_ reason: String) -> String {
        switch language {
        case .en: "Could not check: \(reason)"
        case .fr: "Vérification impossible : \(reason)"
        }
    }

    public func updateFailed(_ reason: String) -> String {
        switch language {
        case .en: "Update failed: \(reason)"
        case .fr: "Échec de la mise à jour : \(reason)"
        }
    }

    public var updateButton: String {
        switch language {
        case .en: "Update"
        case .fr: "Mettre à jour"
        }
    }

    public var checkForUpdatesButton: String {
        switch language {
        case .en: "Check for Updates"
        case .fr: "Rechercher des mises à jour"
        }
    }

    // MARK: Quit

    public var quitTitle: String {
        switch language {
        case .en: "Quit"
        case .fr: "Quitter"
        }
    }

    public var quitButton: String {
        switch language {
        case .en: "Quit \(AppIdentity.name)"
        case .fr: "Quitter \(AppIdentity.name)"
        }
    }

    // MARK: Uninstall

    public var uninstallTitle: String {
        switch language {
        case .en: "Uninstall"
        case .fr: "Désinstaller"
        }
    }

    public var uninstallHint: String {
        switch language {
        case .en: "Gives back the Accessibility permission, removes the entry in Login Items, and "
            + "removes \(AppIdentity.name)'s settings and its update folder. \(AppIdentity.name) then "
            + "moves itself to the Trash and quits."
        case .fr: "Rend la permission d'accessibilité, retire l'entrée dans les éléments d'ouverture "
            + "de session, et supprime les réglages de \(AppIdentity.name) et son dossier de mises à "
            + "jour. \(AppIdentity.name) se met ensuite à la corbeille et quitte."
        }
    }

    public var uninstallWarning: String {
        switch language {
        case .en: "Do not drag \(AppIdentity.name) to the Trash. The Login Items entry and the "
            + "Accessibility permission stay behind, pointing at an app that is gone."
        case .fr: "Ne mettez pas \(AppIdentity.name) à la corbeille vous-même. L'entrée dans les "
            + "éléments d'ouverture de session et la permission d'accessibilité resteraient en place, "
            + "pointant vers une app disparue."
        }
    }

    public var uninstallButton: String {
        switch language {
        case .en: "Uninstall \(AppIdentity.name)"
        case .fr: "Désinstaller \(AppIdentity.name)"
        }
    }

    public var uninstallConfirmTitle: String {
        switch language {
        case .en: "Uninstall \(AppIdentity.name)?"
        case .fr: "Désinstaller \(AppIdentity.name) ?"
        }
    }

    public var uninstallConfirmBody: String {
        switch language {
        case .en: "\(AppIdentity.name) gives back the Accessibility permission, removes the entry in "
            + "Login Items, and removes its settings and its update folder. It then moves itself to "
            + "the Trash and quits."
        case .fr: "\(AppIdentity.name) rend la permission d'accessibilité, retire l'entrée dans les "
            + "éléments d'ouverture de session, et supprime ses réglages et son dossier de mises à "
            + "jour. Il se met ensuite à la corbeille et quitte."
        }
    }

    public var uninstallConfirmButton: String {
        switch language {
        case .en: "Uninstall"
        case .fr: "Désinstaller"
        }
    }

    public var uninstallCancelButton: String {
        switch language {
        case .en: "Cancel"
        case .fr: "Annuler"
        }
    }

    public var uninstallDoneTitle: String {
        switch language {
        case .en: "\(AppIdentity.name) has been removed"
        case .fr: "\(AppIdentity.name) a été désinstallé"
        }
    }

    public var uninstallDoneBody: String {
        switch language {
        case .en: "\(AppIdentity.name) is in the Trash, and nothing it set up is left on the Mac."
        case .fr: "\(AppIdentity.name) est dans la corbeille, et rien de ce qu'il avait installé ne "
            + "reste sur le Mac."
        }
    }

    public var uninstallPartialTitle: String {
        switch language {
        case .en: "\(AppIdentity.name) has been removed, except for this"
        case .fr: "\(AppIdentity.name) a été désinstallé, sauf ceci"
        }
    }

    public var uninstallQuitButton: String {
        switch language {
        case .en: "Quit"
        case .fr: "Quitter"
        }
    }

    public var uninstallGrantFailed: String {
        switch language {
        case .en: "The Accessibility permission could not be given back. Remove \(AppIdentity.name) "
            + "yourself in System Settings, Privacy & Security, Accessibility."
        case .fr: "La permission d'accessibilité n'a pas pu être rendue. Retirez \(AppIdentity.name) "
            + "vous-même dans Réglages Système, Confidentialité et sécurité, Accessibilité."
        }
    }

    /// The reason `uninstallLoginItemFailed` is given when the login item's service did not answer in time.
    /// It reads after a colon and before a full stop.
    public var uninstallNoAnswerReason: String {
        switch language {
        case .en: "macOS did not answer in time"
        case .fr: "macOS n'a pas répondu à temps"
        }
    }

    public func uninstallLoginItemFailed(_ reason: String) -> String {
        switch language {
        case .en: "The Login Items entry could not be removed: \(reason). Remove \(AppIdentity.name) "
            + "yourself in System Settings, General, Login Items."
        case .fr: "L'entrée dans les éléments d'ouverture de session n'a pas pu être retirée : "
            + "\(reason). Retirez \(AppIdentity.name) vous-même dans Réglages Système, Général, "
            + "Ouverture."
        }
    }

    public func uninstallTrashFailed(_ reason: String) -> String {
        switch language {
        case .en: "\(AppIdentity.name) could not move itself to the Trash: \(reason). Drag it there "
            + "from the Applications folder; that is all that is left of it."
        case .fr: "\(AppIdentity.name) n'a pas pu se mettre à la corbeille : \(reason). Faites-le "
            + "depuis le dossier Applications ; c'est tout ce qu'il en reste."
        }
    }

    /// The reason `uninstallHelperFailed` is given when the helper was never started because what it would
    /// have removed could not be shown to be this app's own. It reads after a colon and before a full stop.
    public var uninstallRefusedReason: String {
        switch language {
        case .en: "its files could not be told apart from yours, so none were touched"
        case .fr: "ses fichiers n'ont pas pu être distingués des vôtres, aucun n'a donc été touché"
        }
    }

    public func uninstallHelperFailed(_ reason: String) -> String {
        switch language {
        case .en: "The last step could not be started: \(reason). \(AppIdentity.name)'s settings and "
            + "its folder in Application Support are still there; remove them by hand."
        case .fr: "La dernière étape n'a pas pu démarrer : \(reason). Les réglages de "
            + "\(AppIdentity.name) et son dossier dans Application Support sont toujours là ; "
            + "retirez-les à la main."
        }
    }
}
