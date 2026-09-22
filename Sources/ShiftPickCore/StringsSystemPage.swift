import Foundation

/// The System page: what ShiftPick needs from macOS, and the way to give it.
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

    /// The switch is quoted as the Privacy and Security pane's own strings name it, which is no longer
    /// \u{201C}Accessibility\u{201D}: read it again with `plutil -extract fr xml1` after a macOS release.
    public var accessibilityWarning: String {
        switch language {
        case .en: "In Privacy & Security, \u{201C}Device Control and Data Access\u{201D}, turn on "
            + "\u{201C}\(AppIdentity.name)\u{201D}."
        case .fr: "Dans Confidentialité et sécurité, \u{201C}Contrôle de l\u{2019}appareil et accès aux "
            + "données\u{201D}, activez \u{201C}\(AppIdentity.name)\u{201D}."
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

    // MARK: The click listener

    public var listenerTitle: String {
        switch language {
        case .en: "Click listener"
        case .fr: "Écoute des clics"
        }
    }

    public var listenerHint: String {
        switch language {
        case .en: "\(AppIdentity.name) listens for ⇧ Shift while you click. When macOS interrupts that "
            + "listener too often, \(AppIdentity.name) stops it and waits for you to start it again."
        case .fr: "\(AppIdentity.name) surveille ⇧ Majuscule pendant vos clics. Quand macOS interrompt "
            + "cette écoute trop souvent, \(AppIdentity.name) l'arrête et attend que vous la relanciez."
        }
    }

    public var listenerStoppedWarning: String {
        switch language {
        case .en: "macOS interrupted \(AppIdentity.name) \(K.breakerTrips) times in "
            + "\(Int(K.breakerWindow)) seconds. ⇧ Shift clicks are Finder's until you start listening again."
        case .fr: "macOS a interrompu \(AppIdentity.name) \(K.breakerTrips) fois en "
            + "\(Int(K.breakerWindow)) secondes. Les clics avec ⇧ Majuscule reviennent au Finder jusqu'à "
            + "ce que vous relanciez l'écoute."
        }
    }

    public var startListeningButton: String {
        switch language {
        case .en: "Start Listening Again"
        case .fr: "Réécouter les clics"
        }
    }

    // MARK: Start over

    public var startOverTitle: String {
        switch language {
        case .en: "Start over"
        case .fr: "Recommencer"
        }
    }

    public var showOnboardingButton: String {
        switch language {
        case .en: "Show Onboarding Again"
        case .fr: "Revoir la présentation"
        }
    }
}
