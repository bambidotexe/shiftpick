import Foundation

/// The main menu bar the app puts up although nobody ever sees it. An `LSUIElement` app gets no menu for
/// free, and ⌘Q and ⌘W reach a window only through `NSApplication.mainMenu`, so these standard titles are
/// ours to write, and to translate, rather than macOS's.
///
/// `Quit <App>` is not here: it reads the same in both menus, so it comes from `MenuStrings`.
public struct MainMenuStrings {
    private let language: Language
    init(_ language: Language) { self.language = language }

    public var window: String {
        switch language {
        case .en: "Window"
        case .fr: "Fenêtre"
        }
    }

    public var close: String {
        switch language {
        case .en: "Close"
        case .fr: "Fermer"
        }
    }

    /// macOS's own French for this one is not "Réduire".
    public var minimize: String {
        switch language {
        case .en: "Minimize"
        case .fr: "Placer dans le Dock"
        }
    }
}
