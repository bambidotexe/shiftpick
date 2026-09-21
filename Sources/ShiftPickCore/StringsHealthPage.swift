import Foundation

/// The Health page: every state that says whether ShiftPick is doing its job, at a glance.
///
/// A row's word comes from the shared vocabulary (`StatusWords`) wherever one fits; this table holds the
/// labels, the readings and the sentences that say how to put a row right. The permission's row is labelled
/// and fixed with the System page's own words, so the two pages say the same thing. Console's own name for
/// its crash list is quoted from its loctable (`plutil -extract fr xml1` on
/// `/System/Applications/Utilities/Console.app/Contents/Resources/Localizable.loctable`), like a pane's.
public struct HealthPageStrings {
    private let language: Language
    init(_ language: Language) { self.language = language }

    // MARK: Overview

    public var overviewTitle: String {
        switch language {
        case .en: "Overview"
        case .fr: "Vue d'ensemble"
        }
    }

    public var everythingWorks: String {
        switch language {
        case .en: "Everything works"
        case .fr: "Tout fonctionne"
        }
    }

    public func toLookAt(_ count: Int) -> String {
        switch language {
        case .en: count == 1 ? "1 thing to look at" : "\(count) things to look at"
        case .fr: count == 1 ? "1 point à vérifier" : "\(count) points à vérifier"
        }
    }

    public func notWorking(problems count: Int) -> String {
        switch language {
        case .en: count == 1 ? "Not working: 1 problem" : "Not working: \(count) problems"
        case .fr: count == 1 ? "Ne fonctionne pas : 1 problème" : "Ne fonctionne pas : \(count) problèmes"
        }
    }

    public var checking: String {
        switch language {
        case .en: "Checking"
        case .fr: "Vérification"
        }
    }

    public var checkAgainButton: String {
        switch language {
        case .en: "Check Again"
        case .fr: "Vérifier à nouveau"
        }
    }

    // MARK: Permissions

    /// "Permission" in both languages, as the rest of ShiftPick's French says it.
    public var permissionsTitle: String {
        switch language {
        case .en: "Permissions"
        case .fr: "Permissions"
        }
    }

    /// The tooltip of a permission row that reads *Denied* while macOS's own answer still says granted:
    /// ShiftPick found the grant gone itself, which that answer can go on hiding for seconds.
    public var grantFoundGoneDetail: String {
        switch language {
        case .en: "macOS still reports it as granted, but a request from \(AppIdentity.name) was refused."
        case .fr: "macOS l'indique encore comme accordée, mais une requête de \(AppIdentity.name) a été refusée."
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

    /// The listener is off because the permission is, and starts on its own once it is granted: the
    /// permission's own row, just above, is the red one and says where it is given.
    public var waiting: String {
        switch language {
        case .en: "Waiting"
        case .fr: "En attente"
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

    /// The way back is the one switch the user already knows: turning it on again is what asks for another
    /// try.
    public var listenerStoppedFix: String {
        switch language {
        case .en: "macOS interrupted \(AppIdentity.name) \(K.breakerTrips) times in "
            + "\(Int(K.breakerWindow)) seconds, so it stopped listening for clicks. Turn "
            + "\(AppIdentity.name) off and on again on the Selection page."
        case .fr: "macOS a interrompu \(AppIdentity.name) \(K.breakerTrips) fois en "
            + "\(Int(K.breakerWindow)) secondes, il a donc cessé d'écouter les clics. Désactivez puis "
            + "réactivez \(AppIdentity.name) sur la page Sélection."
        }
    }

    /// Something that ran and is not running any more: the listener macOS kept interrupting, Finder.
    public var stopped: String {
        switch language {
        case .en: "Stopped"
        case .fr: "Arrêté"
        }
    }

    // MARK: Compatibility

    public var compatibilityTitle: String {
        switch language {
        case .en: "Compatibility"
        case .fr: "Compatibilité"
        }
    }

    public var macOSLabel: String {
        switch language {
        case .en: "macOS"
        case .fr: "macOS"
        }
    }

    public var finderLabel: String {
        switch language {
        case .en: "Finder"
        case .fr: "Finder"
        }
    }

    public var running: String {
        switch language {
        case .en: "Running"
        case .fr: "En marche"
        }
    }

    public var finderStoppedFix: String {
        switch language {
        case .en: "Open Finder from the Dock. Until then, ⇧ Shift clicks only work in Open and Save panels."
        case .fr: "Ouvrez le Finder depuis le Dock. D'ici là, les clics avec ⇧ Majuscule ne fonctionnent "
            + "que dans les fenêtres Ouvrir et Enregistrer."
        }
    }

    // MARK: App

    public var appTitle: String {
        switch language {
        case .en: "App"
        case .fr: "App"
        }
    }

    public var launchAtLoginLabel: String {
        switch language {
        case .en: "Launch at login"
        case .fr: "Lancer à la connexion"
        }
    }

    /// The login item was switched off in System Settings while the app still asks for it. Quoted as the
    /// Login Items & Extensions pane names its list.
    public var loginItemNeedsApprovalFix: String {
        switch language {
        case .en: "In System Settings › General › Login Items & Extensions, turn on \(AppIdentity.name) "
            + "under “Open at Login”."
        case .fr: "Dans Réglages Système › Général › Ouverture et extensions, activez \(AppIdentity.name) "
            + "sous « Ouvrir avec la session »."
        }
    }

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

    public func crashesLabel(days: Int) -> String {
        switch language {
        case .en: "Crashes in the last \(days) days"
        case .fr: "Plantages ces \(days) derniers jours"
        }
    }

    public var none: String {
        switch language {
        case .en: "None"
        case .fr: "Aucun"
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
        case .en: "Console shows what happened, under “Crash Reports”. Copy the report below to send it along."
        case .fr: "Console montre ce qui s'est passé, sous « Rapports de blocage ». Copiez le rapport "
            + "ci-dessous pour l'envoyer avec."
        }
    }

    public var locationLabel: String {
        switch language {
        case .en: "Installed in"
        case .fr: "Emplacement"
        }
    }

    public func locationWord(_ location: AppLocation) -> String {
        switch (location, language) {
        case (.applications, _): "Applications"
        case (.elsewhere(let folder), _): folder
        case (.diskImage, .en): "Disk image"
        case (.diskImage, .fr): "Image disque"
        case (.temporaryCopy, .en): "Temporary copy"
        case (.temporaryCopy, .fr): "Copie temporaire"
        }
    }

    public var locationFix: String {
        switch language {
        case .en: "Quit \(AppIdentity.name), drag it to the Applications folder, and open it from there. "
            + "Where it runs now, it cannot update itself."
        case .fr: "Quittez \(AppIdentity.name), glissez-le dans le dossier Applications et ouvrez-le "
            + "depuis là. Là où il tourne, il ne peut pas se mettre à jour."
        }
    }

    // MARK: Report

    public var reportTitle: String {
        switch language {
        case .en: "Report"
        case .fr: "Rapport"
        }
    }

    public var reportHint: String {
        switch language {
        case .en: "Copies everything on this page as text, to paste into a bug report."
        case .fr: "Copie tout le contenu de cette page sous forme de texte, à coller dans un rapport de bug."
        }
    }

    public var copyReportButton: String {
        switch language {
        case .en: "Copy Report"
        case .fr: "Copier le rapport"
        }
    }
}
