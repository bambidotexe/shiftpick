import Foundation

/// The window a launch with no Accessibility permission opens, and which closes itself the moment the
/// permission arrives.
public struct OnboardingStrings {
    private let language: Language
    init(_ language: Language) { self.language = language }

    public var windowTitle: String {
        switch language {
        case .en: "Welcome to \(AppIdentity.name)"
        case .fr: "Bienvenue dans \(AppIdentity.name)"
        }
    }

    public var heading: String {
        switch language {
        case .en: "\(AppIdentity.name) needs Accessibility access"
        case .fr: "\(AppIdentity.name) a besoin de l'accès à l'accessibilité"
        }
    }

    public var body: String {
        switch language {
        case .en: "It uses Accessibility to see which file is under the pointer and to tell Finder "
            + "what to select. Nothing about your files leaves your Mac."
        case .fr: "Il utilise l'accessibilité pour voir quel fichier se trouve sous le pointeur et "
            + "pour indiquer au Finder quoi sélectionner. Rien de ce qui concerne vos fichiers ne "
            + "quitte votre Mac."
        }
    }

    public var steps: String {
        switch language {
        case .en: "1. Click \u{201C}Open Accessibility Settings\u{201D}.\n"
            + "2. Turn on \(AppIdentity.name) in the list.\n"
            + "3. Come back here and the app starts by itself."
        case .fr: "1. Cliquez sur \u{201C}Ouvrir les réglages d'accessibilité\u{201D}.\n"
            + "2. Activez \(AppIdentity.name) dans la liste.\n"
            + "3. Revenez ici : l'app démarre d'elle-même."
        }
    }

    public var openSettingsButton: String {
        switch language {
        case .en: "Open Accessibility Settings"
        case .fr: "Ouvrir les réglages d'accessibilité"
        }
    }
}
