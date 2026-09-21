import Foundation

/// The Selection page: the one thing ShiftPick does, and the one choice about it.
public struct SelectionPageStrings {
    private let language: Language
    init(_ language: Language) { self.language = language }

    public var shiftClickTitle: String {
        switch language {
        case .en: "⇧ Shift-click"
        case .fr: "Clic avec ⇧ Majuscule"
        }
    }

    public var shiftClickHint: String {
        switch language {
        case .en: "Click a file, then hold ⇧ Shift and click another: everything between them is "
            + "selected. A plain click or a ⌘ Command click sets the file the next range is measured "
            + "from, so you can widen and narrow the selection without starting over. Off, ⇧ Shift "
            + "goes back to adding the one file you clicked."
        case .fr: "Cliquez sur un fichier, puis maintenez ⇧ Majuscule et cliquez sur un autre : tout "
            + "ce qui est entre les deux est sélectionné. Un clic simple ou un clic avec ⌘ Commande "
            + "définit le fichier depuis lequel la prochaine plage est mesurée : vous pouvez donc "
            + "élargir ou réduire la sélection sans tout recommencer. Désactivé, ⇧ Majuscule revient "
            + "à n'ajouter que le fichier cliqué."
        }
    }

    public var shiftClickNote: String {
        switch language {
        case .en: "It works in every Finder icon view, on the Desktop, and in Open and Save panels "
            + "shown as icons. List, column and gallery views already do this on their own."
        case .fr: "Cela fonctionne dans toutes les présentations par icônes du Finder, sur le bureau et "
            + "dans les fenêtres Ouvrir et Enregistrer affichées en icônes. Les présentations en liste, "
            + "en colonnes et en galerie le font déjà d'elles-mêmes."
        }
    }

    public var enableToggle: String {
        switch language {
        case .en: "Enable \(AppIdentity.name)"
        case .fr: "Activer \(AppIdentity.name)"
        }
    }

    public var commandShiftToggle: String {
        switch language {
        case .en: "⌘ Command with ⇧ Shift adds the range to the selection"
        case .fr: "⌘ Commande avec ⇧ Majuscule ajoute la plage à la sélection"
        }
    }
}
