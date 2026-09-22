import Foundation

/// The Health page: a table of checks that says whether ShiftPick works, and a table of readings.
///
/// A row's word comes from the shared vocabulary (`StatusWords`) wherever one fits; this table holds the
/// labels, the readings and the sentences that say how to put a row right. The permission's line is labelled
/// and fixed with the System page's own words, so the two pages say the same thing. Console's own name for
/// its crash list is quoted from its loctable (`plutil -extract fr xml1` on
/// `/System/Applications/Utilities/Console.app/Contents/Resources/Localizable.loctable`), like a pane's.
public struct HealthPageStrings {
    private let language: Language
    init(_ language: Language) { self.language = language }

    // MARK: The two tables

    public var healthTitle: String {
        switch language {
        case .en: "Health"
        case .fr: "Santé"
        }
    }

    public var informationTitle: String {
        switch language {
        case .en: "Information"
        case .fr: "Informations"
        }
    }

    public var checkAgainButton: String {
        switch language {
        case .en: "Check Again"
        case .fr: "Vérifier à nouveau"
        }
    }

    // MARK: The permission

    /// The tooltip of a permission row that reads *Denied* while macOS's own answer still says granted:
    /// ShiftPick found the grant gone itself, which that answer can go on hiding for seconds.
    public var grantFoundGoneDetail: String {
        switch language {
        case .en: "macOS still reports it as granted, but a request from \(AppIdentity.name) was refused."
        case .fr: "macOS l'indique encore comme accordée, mais une requête de \(AppIdentity.name) a été refusée."
        }
    }

    // MARK: The click listener

    public var clicksRow: String {
        switch language {
        case .en: "Watching for ⇧ Shift clicks"
        case .fr: "Surveillance des clics avec ⇧ Majuscule"
        }
    }

    public var listenerRefusedFix: String {
        switch language {
        case .en: "macOS would not let \(AppIdentity.name) listen for clicks. Quit it and open it "
            + "again; if that does not help, turn the Accessibility switch off and on."
        case .fr: "macOS n'a pas autorisé \(AppIdentity.name) à écouter les clics. Quittez-le puis "
            + "rouvrez-le ; si cela ne suffit pas, désactivez puis réactivez l'interrupteur "
            + "d'accessibilité."
        }
    }

    /// The way back is a button on the System page, under the listener's own row.
    public var listenerStoppedFix: String {
        switch language {
        case .en: "macOS interrupted \(AppIdentity.name) \(K.breakerTrips) times in "
            + "\(Int(K.breakerWindow)) seconds, so it stopped listening for clicks. Press "
            + "\u{201C}\(SystemPageStrings(language).startListeningButton)\u{201D} on the System page."
        case .fr: "macOS a interrompu \(AppIdentity.name) \(K.breakerTrips) fois en "
            + "\(Int(K.breakerWindow)) secondes, il a donc cessé d'écouter les clics. Cliquez sur "
            + "\u{201C}\(SystemPageStrings(language).startListeningButton)\u{201D} sur la page Système."
        }
    }

    /// Something that ran and is not running any more: the listener macOS kept interrupting, Finder.
    public var stopped: String {
        switch language {
        case .en: "Stopped"
        case .fr: "Arrêté"
        }
    }

    // MARK: Finder

    public var finderLabel: String {
        switch language {
        case .en: "Finder"
        case .fr: "Finder"
        }
    }

    public var finderStoppedFix: String {
        switch language {
        case .en: "Open Finder from the Dock. Until then, ⇧ Shift clicks only work in Open and Save panels."
        case .fr: "Ouvrez le Finder depuis le Dock. D'ici là, les clics avec ⇧ Majuscule ne fonctionnent "
            + "que dans les fenêtres Ouvrir et Enregistrer."
        }
    }

    // MARK: The line every app adds while there is a crash

    public func crashesLabel(days: Int) -> String {
        switch language {
        case .en: "Crashes in the last \(days) days"
        case .fr: "Plantages ces \(days) derniers jours"
        }
    }

    public func lastCrash(_ stamp: String) -> String {
        switch language {
        case .en: "Last one \(stamp)"
        case .fr: "Le dernier le \(stamp)"
        }
    }

    public var crashesFix: String {
        switch language {
        case .en: "Console shows what happened, under “Crash Reports”."
        case .fr: "Console montre ce qui s'est passé, sous « Rapports de blocage »."
        }
    }

    // MARK: Readings

    public var runningForLabel: String {
        switch language {
        case .en: "Running for"
        case .fr: "En marche depuis"
        }
    }

    /// How long something has run, to the minute, in the two largest units that mean anything.
    public func duration(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        switch language {
        case .en:
            if days > 0 { return "\(days) d \(hours) h" }
            if hours > 0 { return "\(hours) h \(minutes) min" }
            return minutes > 0 ? "\(minutes) min" : "Less than a minute"
        case .fr:
            if days > 0 { return "\(days) j \(hours) h" }
            if hours > 0 { return "\(hours) h \(minutes) min" }
            return minutes > 0 ? "\(minutes) min" : "Moins d'une minute"
        }
    }

    public var memoryLabel: String {
        switch language {
        case .en: "Memory used"
        case .fr: "Mémoire utilisée"
        }
    }

    public func megabytes(_ count: Int) -> String {
        switch language {
        case .en: "\(count) MB"
        case .fr: "\(count) Mo"
        }
    }
}
