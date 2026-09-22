import Foundation

/// Everything the user can choose, and the one thing it remembers about them. One switch and nothing
/// else about the feature: ShiftPick does one thing one way, and no setting turns it off or changes it.
///
/// Stored as one JSON blob in `UserDefaults` by `ShiftPickPlatform.SettingsStore`. Every property has a
/// default here and is decoded tolerantly, so a settings file written by an older build, which may carry
/// keys that no longer exist, never resets the rest of it.
public struct Settings: Codable, Equatable, Sendable {
    /// The menu-bar item. Hiding it leaves the app working; opening the bundle again is the way back to
    /// the Settings window.
    public var showInMenuBar: Bool = true

    /// Whether the last page of the onboarding wizard has been reached and its button pressed. Not a
    /// setting: no window shows it, and Settings > System offers the wizard again rather than this flag. A
    /// wizard closed before that last button keeps it false, so it opens again at the next launch.
    public var onboardingCompleted: Bool = false

    public init() {}

    /// Written out rather than synthesised: a key missing from an older file has to fall back to its
    /// default instead of failing the whole decode, and a key an older build wrote is left unread.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Settings()
        showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar)
            ?? fallback.showInMenuBar
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted)
            ?? fallback.onboardingCompleted
    }
}
