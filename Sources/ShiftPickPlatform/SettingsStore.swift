import Combine
import Foundation
import ShiftPickCore

/// Persists `Settings` as one JSON blob in `UserDefaults` and publishes changes to SwiftUI. Every control
/// writes straight through it, so there is no Apply button and no local copy to get out of step.
@MainActor
public final class SettingsStore: ObservableObject {
    public static let defaultsKey = "settings.v1"

    @Published public var settings: Settings {
        didSet { save() }
    }

    private let defaults: UserDefaults

    /// What is on disk is loaded as it is, and nothing else. **No migration belongs here**: `didSet` does
    /// not fire in `init`, so nothing would record that a migration had run and it would re-run at every
    /// launch, overwriting the choice the user had made through the Settings window. A persisted value is
    /// not a default: changing a default in code reaches nobody who has already run the app, and the answer
    /// to that is a control the user can move, not a rule that moves it for them.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = decoded
        } else {
            settings = Settings()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
