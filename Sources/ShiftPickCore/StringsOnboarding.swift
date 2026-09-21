import Foundation

/// The onboarding wizard's four pages: the pitch, the one permission, where the app lives, and "All set".
///
/// The window's own title is the app's name and is not a sentence, so it is not here.
public struct OnboardingStrings {
    private let language: Language
    init(_ language: Language) { self.language = language }

    // MARK: The pitch

    public var pitchHeadline: String {
        switch language {
        case .en: "The whole range, even in icon view."
        case .fr: "La plage entière, même en vue par icônes."
        }
    }

    /// The one word of the headline drawn in the app's colour. Localized on its own, so the French accents
    /// its own word and not a fragment of another.
    public var pitchAccent: String {
        switch language {
        case .en: "range"
        case .fr: "plage"
        }
    }

    public var pitchBody: String {
        switch language {
        case .en: "Click a file, hold ⇧ Shift, click another: everything between them is selected. "
            + "Finder does that in its list, column and gallery views. \(AppIdentity.name) does it in "
            + "icon view and on the Desktop, and nothing else."
        case .fr: "Cliquez sur un fichier, maintenez ⇧ Majuscule, cliquez sur un autre : tout ce qui "
            + "se trouve entre les deux est sélectionné. Le Finder le fait en vue par liste, par "
            + "colonnes et par galerie. \(AppIdentity.name) le fait en vue par icônes et sur le bureau, "
            + "et rien d'autre."
        }
    }

    public var pitchIconViewPill: String {
        switch language {
        case .en: "Icon views"
        case .fr: "Vues par icônes"
        }
    }

    public var pitchDesktopPill: String {
        switch language {
        case .en: "Desktop"
        case .fr: "Bureau"
        }
    }

    public var pitchPanelsPill: String {
        switch language {
        case .en: "Open and Save"
        case .fr: "Ouvrir et Enregistrer"
        }
    }

    // MARK: The permission

    public var permissionHeader: String {
        switch language {
        case .en: "Permission"
        case .fr: "Permission"
        }
    }

    public var permissionIntro: String {
        switch language {
        case .en: "\(AppIdentity.name) needs one permission from macOS and can do nothing at all "
            + "without it. The system's own dialog calls it Accessibility; the Privacy and Security "
            + "pane lists it under the name below."
        case .fr: "\(AppIdentity.name) a besoin d'une seule permission de macOS et ne peut rien faire "
            + "sans elle. La fenêtre du système l'appelle Accessibilité ; le volet Confidentialité et "
            + "sécurité la classe sous le nom ci-dessous."
        }
    }

    /// **Exactly what the Privacy and Security pane calls this grant**, quoted from
    /// `SecurityPrivacyExtension.appex`'s own strings, curly apostrophe and all. Read again with
    /// `plutil -extract fr xml1` after a macOS release: the name has changed once already.
    public var accessibilityTitle: String {
        switch language {
        case .en: "Device Control and Data Access"
        case .fr: "Contrôle de l\u{2019}appareil et accès aux données"
        }
    }

    public var accessibilityWhy: String {
        switch language {
        case .en: "Lets \(AppIdentity.name) see which file is under the pointer and tell Finder what to "
            + "select. Nothing about your files ever leaves your Mac."
        case .fr: "Permet à \(AppIdentity.name) de voir quel fichier se trouve sous le pointeur et "
            + "d'indiquer au Finder quoi sélectionner. Rien de ce qui concerne vos fichiers ne quitte "
            + "votre Mac."
        }
    }

    public var allowButton: String {
        switch language {
        case .en: "Allow…"
        case .fr: "Autoriser…"
        }
    }

    /// The tooltip and the accessibility description of the mark beside a row the app cannot work without.
    public var requiredMark: String {
        switch language {
        case .en: "Required"
        case .fr: "Requis"
        }
    }

    // MARK: Where it lives

    public var homeHeader: String {
        switch language {
        case .en: "Where it lives"
        case .fr: "Où il se trouve"
        }
    }

    public var homeIntro: String {
        switch language {
        case .en: "Neither of these is required. \(AppIdentity.name) has no window of its own and no "
            + "icon in the Dock: it waits in the menu bar. Both can be changed later in Settings."
        case .fr: "Facultatif. \(AppIdentity.name) n'a pas de fenêtre à lui ni d'icône dans le Dock : "
            + "il attend dans la barre des menus. Ces deux réglages sont modifiables plus tard dans les "
            + "réglages."
        }
    }

    /// **Exactly what the Login Items and Extensions pane calls the list the app appears in**, quoted from
    /// `LoginItems.appex`'s own strings.
    public var openAtLoginTitle: String {
        switch language {
        case .en: "Open at Login"
        case .fr: "Ouvrir avec la session"
        }
    }

    public var openAtLoginWhy: String {
        switch language {
        case .en: "Starts \(AppIdentity.name) when you log in, so the gesture is there without opening "
            + "anything. It starts with no window."
        case .fr: "Lance \(AppIdentity.name) à l'ouverture de votre session, pour que le geste soit là "
            + "sans rien ouvrir. Il démarre sans fenêtre."
        }
    }

    public var menuBarWhy: String {
        switch language {
        case .en: "Its menu holds the switch and the way back to these settings. Hidden, "
            + "\(AppIdentity.name) keeps working: open it again from the Applications folder to get the "
            + "window back."
        case .fr: "Son menu contient l'interrupteur et le chemin de retour vers ces réglages. Masquée, "
            + "\(AppIdentity.name) continue de fonctionner : rouvrez-le depuis le dossier Applications "
            + "pour revenir à la fenêtre."
        }
    }

    public var turnOnButton: String {
        switch language {
        case .en: "Turn On"
        case .fr: "Activer"
        }
    }

    public var turnOffButton: String {
        switch language {
        case .en: "Turn Off"
        case .fr: "Désactiver"
        }
    }

    // MARK: All set

    public var doneHeadline: String {
        switch language {
        case .en: "All set"
        case .fr: "Tout est prêt"
        }
    }

    public var doneBody: String {
        switch language {
        case .en: "Click a file, hold ⇧ Shift, and click another. Look for \(AppIdentity.name) in the "
            + "menu bar, at the top right, whenever you want to turn it off or change something."
        case .fr: "Cliquez sur un fichier, maintenez ⇧ Majuscule et cliquez sur un autre. Retrouvez "
            + "\(AppIdentity.name) dans la barre des menus, en haut à droite, pour le désactiver ou "
            + "changer un réglage."
        }
    }

    // MARK: The stepping button

    public var continueButton: String {
        switch language {
        case .en: "Continue"
        case .fr: "Continuer"
        }
    }

    /// What the stepping button reads until the page's own rule is met.
    public var skipButton: String {
        switch language {
        case .en: "Skip"
        case .fr: "Passer"
        }
    }

    public var finishButton: String {
        switch language {
        case .en: "Finish"
        case .fr: "Terminer"
        }
    }
}
