import Foundation

/// Everything the user can choose. Three switches and nothing else: ShiftPick does one thing, and no
/// setting restricts where it does it.
///
/// Stored as one JSON blob in `UserDefaults` by `ShiftPickPlatform.SettingsStore`. Every property has a
/// default here and is decoded tolerantly, so a settings file written by an older build never resets the
/// rest of it.
public struct Settings: Codable, Equatable, Sendable {
    /// The kill switch. Off, every click is returned to the system untouched and Finder's own ⇧ Shift
    /// behaviour comes back. It takes effect on the next click, not on the next launch.
    public var enabled: Bool = true

    /// On, ⌘ Command held with ⇧ Shift adds the range to what is already selected instead of replacing it.
    /// Off, ⌘ Command with ⇧ Shift is left to Finder.
    public var commandShiftAdds: Bool = true

    /// The menu-bar item. Hiding it leaves the app working; opening the bundle again is the way back to
    /// the Settings window.
    public var showInMenuBar: Bool = true

    public init() {}

    /// Written out rather than synthesised: a key missing from an older file has to fall back to its
    /// default instead of failing the whole decode, which would throw away the other two.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Settings()
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? fallback.enabled
        commandShiftAdds = try container.decodeIfPresent(Bool.self, forKey: .commandShiftAdds)
            ?? fallback.commandShiftAdds
        showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar)
            ?? fallback.showInMenuBar
    }
}
