import Foundation

/// The one word a status mark carries, from the window's fixed vocabulary. Shared by every page so that the
/// same state never gets two words.
public struct StatusWords {
    private let language: Language
    init(_ language: Language) { self.language = language }

    public var granted: String {
        switch language {
        case .en: "Granted"
        case .fr: "Accordée"
        }
    }

    public var denied: String {
        switch language {
        case .en: "Denied"
        case .fr: "Refusée"
        }
    }

    public var enabled: String {
        switch language {
        case .en: "Enabled"
        case .fr: "Activé"
        }
    }

    public var disabled: String {
        switch language {
        case .en: "Disabled"
        case .fr: "Désactivé"
        }
    }

    public var failed: String {
        switch language {
        case .en: "Failed"
        case .fr: "Échec"
        }
    }
}

/// Everything the Settings window shows: the page titles, the shared status vocabulary, and one table per
/// page.
public struct SettingsStrings {
    private let language: Language
    init(_ language: Language) { self.language = language }

    public var pageGeneral: String {
        switch language {
        case .en: "General"
        case .fr: "Général"
        }
    }

    public var pageHealth: String {
        switch language {
        case .en: "Health"
        case .fr: "Santé"
        }
    }

    public var pageTip: String {
        switch language {
        case .en: "Tip"
        case .fr: "Don"
        }
    }

    public var pageSystem: String {
        switch language {
        case .en: "System"
        case .fr: "Système"
        }
    }

    public var words: StatusWords { StatusWords(language) }
    public var general: GeneralPageStrings { GeneralPageStrings(language) }
    public var tip: TipPageStrings { TipPageStrings(language) }
    public var system: SystemPageStrings { SystemPageStrings(language) }
    public var health: HealthPageStrings { HealthPageStrings(language) }
}
