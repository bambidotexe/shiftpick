import Foundation

/// The languages ShiftPick speaks. English is the fallback: every language that is not French is shown in
/// English.
///
/// Adding a case here is a compile error in every string table until each one answers for the new language,
/// which is the point: no string can exist in one language only.
public enum Language: String, CaseIterable, Sendable {
    case en, fr

    /// The rule that turns the system's preferred language into one of ours. The tag is BCP-47, so the
    /// primary subtag is what decides: `fr`, `fr-FR` and `fr-CA` are French, `fry` (Frisian) is not.
    ///
    /// The tag is passed in. Core never asks the system anything, so this rule is testable without a system
    /// to ask.
    public init(preferredLanguage tag: String?) {
        let primary = tag?.split(whereSeparator: { $0 == "-" || $0 == "_" }).first?.lowercased()
        self = primary == "fr" ? .fr : .en
    }
}

/// The one language every string table reads.
///
/// `ShiftPickApp` sets it once at launch, before it builds a window, a menu or a status item.
///
/// Locked because those readers are not on one queue: the settings window reads from the main queue while
/// the click path, which logs in English only, runs on the run loop the event tap is on.
public enum Loc {
    private static let lock = NSLock()
    private static var current: Language = .en

    public static var language: Language {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    public static var menu: MenuStrings { MenuStrings(language) }
    public static var mainMenu: MainMenuStrings { MainMenuStrings(language) }
    public static var onboarding: OnboardingStrings { OnboardingStrings(language) }
    public static var settings: SettingsStrings { SettingsStrings(language) }
    public static var update: UpdateStrings { UpdateStrings(language) }
    public static var updateWindow: UpdateWindowStrings { UpdateWindowStrings(language) }
}
