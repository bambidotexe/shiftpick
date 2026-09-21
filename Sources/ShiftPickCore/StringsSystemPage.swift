import Foundation

/// The System page: what ShiftPick needs from macOS, and whether it has it.
public struct SystemPageStrings {
    private let language: Language
    init(_ language: Language) { self.language = language }

    public var accessibilityTitle: String {
        switch language {
        case .en: "Accessibility"
        case .fr: "Accessibilité"
        }
    }

    public var accessibilityHint: String {
        switch language {
        case .en: "The only permission \(AppIdentity.name) needs. It lets it see which file is under "
            + "the pointer and tell Finder what to select."
        case .fr: "La seule permission dont \(AppIdentity.name) a besoin. Elle lui permet de voir "
            + "quel fichier se trouve sous le pointeur et d'indiquer au Finder quoi sélectionner."
        }
    }

    public var accessibilityNote: String {
        switch language {
        case .en: "Nothing about your files ever leaves your Mac."
        case .fr: "Rien de ce qui concerne vos fichiers ne quitte votre Mac."
        }
    }

    public var accessibilityWarning: String {
        switch language {
        case .en: "In Privacy & Security, Accessibility, turn on \u{201C}\(AppIdentity.name)\u{201D}."
        case .fr: "Dans Confidentialité et sécurité, Accessibilité, activez \u{201C}\(AppIdentity.name)\u{201D}."
        }
    }

    public var accessibilityRow: String {
        switch language {
        case .en: "Accessibility permission"
        case .fr: "Permission d'accessibilité"
        }
    }

    public var openAccessibilityButton: String {
        switch language {
        case .en: "Open Accessibility Settings"
        case .fr: "Ouvrir les réglages d'accessibilité"
        }
    }

    // MARK: Clicks

    public var clicksTitle: String {
        switch language {
        case .en: "Clicks"
        case .fr: "Clics"
        }
    }

    public var clicksHint: String {
        switch language {
        case .en: "\(AppIdentity.name) watches for a click with ⇧ Shift held and lets every other "
            + "click through untouched."
        case .fr: "\(AppIdentity.name) surveille les clics avec ⇧ Majuscule enfoncée et laisse passer "
            + "tous les autres clics tels quels."
        }
    }

    public var clicksRow: String {
        switch language {
        case .en: "Watching for clicks"
        case .fr: "Surveillance des clics"
        }
    }

    public var clicksWarningNoTap: String {
        switch language {
        case .en: "macOS would not let \(AppIdentity.name) listen for clicks. Quit it and open it "
            + "again; if that does not help, turn the Accessibility switch off and on."
        case .fr: "macOS n'a pas autorisé \(AppIdentity.name) à écouter les clics. Quittez-le puis "
            + "rouvrez-le ; si cela ne suffit pas, désactivez puis réactivez l'interrupteur "
            + "d'accessibilité."
        }
    }

    public var clicksWarningDisabled: String {
        switch language {
        case .en: "\(AppIdentity.name) is off. Turn it on again on the Selection page."
        case .fr: "\(AppIdentity.name) est désactivé. Réactivez-le sur la page Sélection."
        }
    }
}
