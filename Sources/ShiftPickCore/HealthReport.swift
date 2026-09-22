import Foundation

/// Everything the Health page reports, as values. The app gathers them (`Platform` reads the system, `App`
/// reads its own state and the engine's); this layer turns them into the page's two tables, so what a fact
/// reads as, in which colour and with which sentence, is decided here and tested.
public struct HealthFacts: Equatable, Sendable {
    /// The Accessibility grant **as ShiftPick can use it**: macOS's cached answer, except once ShiftPick has
    /// found the grant gone itself (`TapLifecycle.Status.showsGrant`). Never the cached answer alone.
    public var accessibilityGranted: Bool
    /// What macOS's cached answer says on its own, for the line's tooltip when the two disagree.
    public var accessibilitySystemSays: Bool
    /// Whether the onboarding wizard marks the grant required, so that the Health page, the System page and
    /// the wizard colour a missing grant the same way.
    public var accessibilityRequired: Bool
    /// What the click listener is doing, as the engine last reported it.
    public var listener: TapLifecycle.Status
    /// The *Enable ShiftPick* switch.
    public var userEnabled: Bool
    /// Whether Finder is running; nil until it has been read.
    public var finderRunning: Bool?
    /// How long this process has been running, nil when the system would not say.
    public var runningSeconds: TimeInterval?
    /// The memory this process holds, as Activity Monitor counts it; nil when the system would not say.
    public var memoryBytes: UInt64?
    /// When each crash report of this app in the last `K.healthCrashWindow` was written, newest first.
    public var recentCrashes: [Date]

    public init(accessibilityGranted: Bool, accessibilitySystemSays: Bool, accessibilityRequired: Bool,
                listener: TapLifecycle.Status, userEnabled: Bool, finderRunning: Bool?,
                runningSeconds: TimeInterval?, memoryBytes: UInt64?, recentCrashes: [Date]) {
        self.accessibilityGranted = accessibilityGranted
        self.accessibilitySystemSays = accessibilitySystemSays
        self.accessibilityRequired = accessibilityRequired
        self.listener = listener
        self.userEnabled = userEnabled
        self.finderRunning = finderRunning
        self.runningSeconds = runningSeconds
        self.memoryBytes = memoryBytes
        self.recentCrashes = recentCrashes
    }
}

/// The Health page's two tables: the checks, green, orange or red, and the readings, blue.
///
/// **A check is something that has to be in place or running for ShiftPick to work**: the permission, the
/// click listener, Finder. A preference is never a check, whichever way it is set (the *Enable ShiftPick*
/// switch, Launch at login), and neither is a reading. The skill `macos-building-settings-pages` (*The
/// Health page*) holds the rules and every app's list.
public enum HealthReport {
    /// The Health table, in page order: the permission, always; the click listener, while it is switched on
    /// and past waiting for the permission; Finder, only while it is not running; the crashes, only while
    /// there is one. Four lines at the very most.
    public static func checks(for facts: HealthFacts) -> [HealthRow] {
        [accessibility(facts), listener(facts), finder(facts), crashes(facts.recentCrashes)].compactMap { $0 }
    }

    /// The Information table: how long ShiftPick has been up, and what it holds. The last ⇧ Shift click would
    /// say more, and it lives in the safety layer (`scripts/safety-gates.sh`), which a reading does not
    /// reach into.
    public static func readings(for facts: HealthFacts) -> [InfoRow] {
        let t = Loc.settings.health
        var rows: [InfoRow] = []
        if let seconds = facts.runningSeconds {
            rows.append(InfoRow(id: "running for", label: t.runningForLabel, value: t.duration(seconds: seconds)))
        }
        if let bytes = facts.memoryBytes {
            rows.append(InfoRow(id: "memory", label: t.memoryLabel,
                                value: t.megabytes(Int((Double(bytes) / 1_048_576).rounded()))))
        }
        return rows
    }

    /// The one permission, labelled as the System page labels it and coloured by the same rule. When the
    /// grant reads *Denied* while macOS's own answer still says yes, the tooltip says so.
    static func accessibility(_ facts: HealthFacts) -> HealthRow {
        let words = Loc.settings.words
        let held = facts.accessibilityGranted
        return HealthRow(id: "accessibility", label: Loc.settings.system.accessibilityRow,
                         level: HealthRules.grant(held: held, required: facts.accessibilityRequired),
                         word: held ? words.granted : words.denied,
                         detail: !held && facts.accessibilitySystemSays ? Loc.settings.health.grantFoundGoneDetail : nil,
                         fix: Loc.settings.system.accessibilityWarning)
    }

    /// Whether ShiftPick is watching for ⇧ Shift clicks, and if it is not while it should be, why and what puts
    /// it right. No line in the three cases `HealthRules.listener` answers nil for.
    static func listener(_ facts: HealthFacts) -> HealthRow? {
        guard let level = HealthRules.listener(facts.listener, userEnabled: facts.userEnabled) else { return nil }
        let t = Loc.settings.health
        let words = Loc.settings.words
        let (word, fix): (String, String?) = switch facts.listener {
        case .refused: (words.failed, t.listenerRefusedFix)
        case .breakerOpen: (t.stopped, t.listenerStoppedFix)
        case .watching, .needsPermission, .stopped: (words.enabled, nil)
        }
        // The engine's own name for its state, untranslated: an identifier a bug report wants as it is.
        return HealthRow(id: "listener", label: t.clicksRow, level: level, word: word,
                         detail: "\(facts.listener)", fix: fix)
    }

    /// Finder, only while it is not running: running, it has nothing to say. Not running, only the Open and
    /// Save panels shown as icons are left, so ShiftPick is degraded rather than stopped: orange.
    static func finder(_ facts: HealthFacts) -> HealthRow? {
        guard facts.finderRunning == false else { return nil }
        let t = Loc.settings.health
        return HealthRow(id: "finder", label: t.finderLabel, level: .warning, word: t.stopped,
                         fix: t.finderStoppedFix)
    }

    /// The line every app of the family ends its Health table with, **only while there is a crash** in the
    /// last `K.healthCrashWindow`: a crash is a problem while it is recent, and no crash is nothing to say.
    public static func crashes(_ recentCrashes: [Date]) -> HealthRow? {
        guard let last = recentCrashes.first else { return nil }
        let t = Loc.settings.health
        return HealthRow(id: "crashes", label: t.crashesLabel(days: Int(K.healthCrashWindow / 86_400)),
                         level: .warning, word: "\(recentCrashes.count)", detail: t.lastCrash(stamp(last)),
                         fix: t.crashesFix)
    }

    /// A moment as a tooltip wants it: the same in every language, sortable, to the minute, in the Mac's own
    /// time zone.
    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
