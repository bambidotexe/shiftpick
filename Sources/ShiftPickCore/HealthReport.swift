import Foundation

/// Everything the Health page reports, as values. The app gathers them (`Platform` reads the system, `App`
/// reads its own state and the engine's); this layer turns them into the page's groups, so what a fact
/// reads as, in which colour and with which sentence, is decided here and tested.
public struct HealthFacts: Equatable, Sendable {
    // MARK: Permissions

    /// The Accessibility grant **as ShiftPick can use it**: macOS's cached answer, except once ShiftPick has
    /// found the grant gone itself (`TapLifecycle.Status.showsGrant`). Never the cached answer alone.
    public var accessibilityGranted: Bool
    /// What macOS's cached answer says on its own, for the row's detail when the two disagree.
    public var accessibilitySystemSays: Bool
    /// Whether the onboarding wizard marks the grant required, so that the Health page, the System page and
    /// the wizard colour a missing grant the same way.
    public var accessibilityRequired: Bool

    // MARK: Clicks

    /// What the click listener is doing, as the engine last reported it.
    public var listener: TapLifecycle.Status
    /// The *Enable ShiftPick* switch.
    public var userEnabled: Bool

    // MARK: Compatibility

    /// The macOS version, "27.0" or "27.0.1"; nil until it has been read.
    public var macOSVersion: String?
    /// macOS's own description of itself, build included, for the row's detail.
    public var macOSBuild: String?
    /// Whether Finder is running; nil until it has been read.
    public var finderRunning: Bool?

    // MARK: App

    public var loginItem: LoginItemState
    /// How long this process has been running, nil when the system would not say.
    public var runningSeconds: TimeInterval?
    /// The memory this process holds, as Activity Monitor counts it; nil when the system would not say.
    public var memoryBytes: UInt64?
    /// When each crash report of this app in the last `K.healthCrashWindow` was written, newest first.
    public var recentCrashes: [Date]
    public var location: AppLocation
    /// Where the running bundle is, for the location row's tooltip and the report.
    public var bundlePath: String

    public init(accessibilityGranted: Bool, accessibilitySystemSays: Bool, accessibilityRequired: Bool,
                listener: TapLifecycle.Status, userEnabled: Bool,
                macOSVersion: String?, macOSBuild: String?, finderRunning: Bool?,
                loginItem: LoginItemState, runningSeconds: TimeInterval?, memoryBytes: UInt64?,
                recentCrashes: [Date], location: AppLocation, bundlePath: String) {
        self.accessibilityGranted = accessibilityGranted
        self.accessibilitySystemSays = accessibilitySystemSays
        self.accessibilityRequired = accessibilityRequired
        self.listener = listener
        self.userEnabled = userEnabled
        self.macOSVersion = macOSVersion
        self.macOSBuild = macOSBuild
        self.finderRunning = finderRunning
        self.loginItem = loginItem
        self.runningSeconds = runningSeconds
        self.memoryBytes = memoryBytes
        self.recentCrashes = recentCrashes
        self.location = location
        self.bundlePath = bundlePath
    }
}

/// The Health page's groups, and the text Copy Report puts on the clipboard.
public enum HealthReport {
    /// The groups under the overview, in page order: the permission, the clicks, what ShiftPick leans on in
    /// macOS, and the app itself.
    public static func groups(for facts: HealthFacts) -> [HealthGroup] {
        [permissionsGroup(facts), clicksGroup(facts), compatibilityGroup(facts), appGroup(facts)]
            .compactMap { $0 }
    }

    /// The one permission, labelled as the System page labels it and coloured by the same rule.
    static func permissionsGroup(_ facts: HealthFacts) -> HealthGroup {
        let t = Loc.settings.health
        let system = Loc.settings.system
        let words = Loc.settings.words
        let held = facts.accessibilityGranted
        let row = HealthRow(id: "accessibility", label: system.accessibilityRow,
                            level: HealthRules.grant(held: held, required: facts.accessibilityRequired),
                            word: held ? words.granted : words.denied,
                            detail: !held && facts.accessibilitySystemSays ? t.grantFoundGoneDetail : nil,
                            fix: system.accessibilityWarning)
        return HealthGroup(id: "permissions", title: t.permissionsTitle, rows: [row])
    }

    /// The click listener: whether ShiftPick is watching for ⇧ Shift clicks, and if it is not while it is
    /// switched on, why, and what puts it right. Nil before anything has been reported.
    static func clicksGroup(_ facts: HealthFacts) -> HealthGroup? {
        guard let level = HealthRules.listener(facts.listener, userEnabled: facts.userEnabled) else { return nil }
        let t = Loc.settings.health
        let words = Loc.settings.words
        let word: String
        let fix: String?
        switch (facts.userEnabled, facts.listener) {
        case (false, _): word = words.disabled; fix = nil
        case (true, .watching): word = words.enabled; fix = nil
        case (true, .needsPermission): word = t.waiting; fix = nil
        case (true, .refused): word = words.failed; fix = t.listenerRefusedFix
        case (true, .breakerOpen): word = t.stopped; fix = t.listenerStoppedFix
        case (true, .stopped): return nil
        }
        // The engine's own name for its state, untranslated: an identifier a bug report wants as it is.
        let row = HealthRow(id: "listener", label: t.clicksRow, level: level, word: word,
                            detail: "\(facts.listener)", fix: fix)
        return HealthGroup(id: "clicks", title: t.clicksTitle, hint: t.clicksHint, rows: [row])
    }

    /// What ShiftPick leans on in macOS: the version it runs on, and Finder. Nil before either was read.
    static func compatibilityGroup(_ facts: HealthFacts) -> HealthGroup? {
        let t = Loc.settings.health
        var rows: [HealthRow] = []
        if let version = facts.macOSVersion {
            rows.append(HealthRow(id: "macos", label: t.macOSLabel, level: .info, word: version,
                                  detail: facts.macOSBuild))
        }
        if let running = facts.finderRunning {
            rows.append(HealthRow(id: "finder", label: t.finderLabel, level: HealthRules.finder(running: running),
                                  word: running ? t.running : t.stopped, fix: t.finderStoppedFix))
        }
        return rows.isEmpty ? nil : HealthGroup(id: "compatibility", title: t.compatibilityTitle, rows: rows)
    }

    /// What every app of the family reports about itself: whether it comes back at login, how long it has
    /// been up, what it holds, whether it has crashed, and whether it is installed at all.
    static func appGroup(_ facts: HealthFacts) -> HealthGroup {
        let t = Loc.settings.health
        let words = Loc.settings.words
        var rows: [HealthRow] = []

        rows.append(HealthRow(id: "login item", label: t.launchAtLoginLabel,
                              level: HealthRules.loginItem(facts.loginItem),
                              word: facts.loginItem == .enabled ? words.enabled : words.disabled,
                              fix: t.loginItemNeedsApprovalFix))

        if let seconds = facts.runningSeconds {
            rows.append(HealthRow(id: "running for", label: t.runningForLabel, level: .info,
                                  word: t.duration(seconds: seconds)))
        }
        if let bytes = facts.memoryBytes {
            rows.append(HealthRow(id: "memory", label: t.memoryLabel, level: .info,
                                  word: t.megabytes(Int((Double(bytes) / 1_048_576).rounded()))))
        }

        let crashes = facts.recentCrashes.count
        rows.append(HealthRow(id: "crashes", label: t.crashesLabel(days: Int(K.healthCrashWindow / 86_400)),
                              level: HealthRules.crashes(crashes),
                              word: crashes == 0 ? t.none : "\(crashes)",
                              detail: facts.recentCrashes.first.map { t.lastCrash(stamp($0)) },
                              fix: t.crashesFix))

        rows.append(HealthRow(id: "location", label: t.locationLabel,
                              level: HealthRules.location(facts.location),
                              word: t.locationWord(facts.location), detail: facts.bundlePath,
                              fix: t.locationFix))

        return HealthGroup(id: "app", title: t.appTitle, rows: rows)
    }

    /// The first row's word: everything works, how many lines to look at, or how many stop the app.
    public static func summaryWord(_ summary: HealthSummary) -> String {
        let t = Loc.settings.health
        switch summary.level {
        case .failure: return t.notWorking(problems: summary.blocking)
        case .warning: return t.toLookAt(summary.toLookAt)
        case .good, .info: return t.everythingWorks
        }
    }

    /// The copied report: which app and which system, the summary, then every group of the page with one
    /// line per row, its level, its word and its detail. Written for a bug report, so nothing in it is a
    /// secret: a row that reads one masks it before it gets here.
    public static func text(appName: String, version: String, system: String, groups: [HealthGroup]) -> String {
        var lines = ["\(appName) \(version), \(system)", summaryWord(HealthSummary(groups: groups))]
        for group in groups {
            lines.append("")
            lines.append(group.title)
            for row in group.rows {
                var line = "\(tag(row.level)) \(row.label): \(row.word)"
                if let detail = row.detail, !detail.isEmpty { line += " (\(detail))" }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func tag(_ level: HealthLevel) -> String {
        switch level {
        case .info: "[INFO]"
        case .good: "[OK]  "
        case .warning: "[WARN]"
        case .failure: "[FAIL]"
        }
    }

    /// A moment as a bug report wants it: the same in every language, sortable, to the minute, in the Mac's
    /// own time zone.
    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
