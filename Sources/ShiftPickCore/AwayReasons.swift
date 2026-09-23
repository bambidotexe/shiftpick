import Foundation

/// Why nobody can be clicking, and what that does to the click listener.
///
/// Nothing is armed while the Mac is asleep, the screen is locked, or another user's session is in front
/// (`docs/functional.md` §0). Each of those is a reason, heard going and heard ending by a pair of
/// notifications of its own, and the listener is suspended for exactly as long as one is held: the first
/// reason heard suspends it, and **the last one to end resumes it, whichever it is, in whichever order they
/// end, and whether it ends by its own notification or by the session's answer**. A set that was only looked
/// at once it had been emptied left the listener suspended for good (`docs/pitfalls.md` 17).
///
/// **No notification is trusted to arrive.** A lid closed both sleeps and locks; the way back can wake the
/// Mac with the lock screen still up, or unlock it before any wake notice comes, and the order is promised
/// by nothing (`docs/macOS.md`, *Sleep and the lock screen*). So at every piece of news, a notification of
/// coming back, whether its reason was heard going or not, and ⇧ Shift heard while the listener is
/// suspended, the reasons are held against what the session says itself: any news at all is a Mac that is
/// awake, and the session says whether its screen is locked and whether it is the one on the console.
///
/// It is a value: a notification or the session's answer goes in, what to do about it comes out. The
/// notifications, the session dictionary and the engine are `AppDelegate`'s, which does what the effects say
/// and decides nothing.
public struct AwayReasons: Equatable, Sendable {
    public enum Reason: String, CaseIterable, Equatable, Sendable {
        case asleep, locked, anotherSession
    }

    /// What the session says about itself (`CGSessionCopyCurrentDictionary`), read at every piece of news.
    public struct Session: Equatable, Sendable {
        /// `CGSSessionScreenIsLocked`: present and true only while the screen is locked.
        public var screenIsLocked: Bool
        /// `kCGSessionOnConsoleKey`: true while this session is the one on the console. False when the
        /// dictionary would not say, which keeps the listener suspended rather than arming it in a session
        /// nobody can be clicking in.
        public var onConsole: Bool

        public init(screenIsLocked: Bool, onConsole: Bool) {
            self.screenIsLocked = screenIsLocked
            self.onConsole = onConsole
        }
    }

    public enum Effect: Equatable, Sendable {
        case suspend
        case resume
        /// One line at notice level. Nothing here moves in silence: a suspension nobody could see the end of
        /// would be an app that silently does nothing.
        case log(String)
    }

    /// The reasons heard going and not yet ended.
    public private(set) var held: Set<Reason> = []
    /// Whether the listener has been told to suspend and not yet told to resume. **It is true exactly while
    /// a reason is held**, which `AwayReasonsTests` holds after every event of a seeded run.
    public private(set) var isSuspended = false

    public init() {}

    /// A notification that a reason has begun. Heard twice is heard once, and the listener is suspended for
    /// the first reason and not again for the next.
    public mutating func went(away reason: Reason) -> [Effect] {
        guard held.insert(reason).inserted else { return [] }
        var effects: [Effect] = [.log("away (\(reason.rawValue)); nothing arms until it is over")]
        if !isSuspended {
            isSuspended = true
            effects.append(.suspend)
        }
        return effects
    }

    /// A notification that a reason has ended. While anything is held it is news, whether or not this reason
    /// was among what was held: the reason is put down and the rest are held against the session. With
    /// nothing held there is nothing to come back from.
    public mutating func came(backFrom reason: Reason, session: Session) -> [Effect] {
        guard !held.isEmpty else { return [] }
        held.remove(reason)
        return reconcile(because: "back (\(reason.rawValue))", session: session)
    }

    /// ⇧ Shift heard while the listener says it is suspended: somebody is at the keyboard, so a notification
    /// that would have said so may have been lost. **Answered from the session alone, whatever is held**: the
    /// listener asked because it is suspended, and what is held is not what it is checked against.
    public mutating func shiftPressed(session: Session) -> [Effect] {
        reconcile(because: "⇧ Shift was pressed", session: session)
    }

    /// Any news at all is a Mac that is awake; the session says the rest. What is left is said, and with
    /// nothing left the listener resumes.
    private mutating func reconcile(because news: String, session: Session) -> [Effect] {
        held.remove(.asleep)
        if !session.screenIsLocked { held.remove(.locked) }
        if session.onConsole { held.remove(.anotherSession) }
        let left = held.map(\.rawValue).sorted().joined(separator: ", ")
        var effects: [Effect] = [.log(left.isEmpty ? "\(news); nothing is away any more" : "\(news); still away: \(left)")]
        if held.isEmpty {
            isSuspended = false
            effects.append(.resume)
        }
        return effects
    }
}
