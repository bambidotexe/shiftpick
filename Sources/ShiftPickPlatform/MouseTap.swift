import AppKit
import CoreGraphics
import ShiftPickCore

/// The one event tap. It listens for the left mouse button going down and coming up, and it is allowed to
/// swallow an event, which a listen-only tap could not do.
///
/// **The ⇧ Shift flag is read before anything else**, so a click that is not ShiftPick's business leaves
/// the callback after one bit test and a branch. Nothing else is subscribed: no moves, no drags, no
/// modifier changes. The callback runs on the main run loop, because that is where the tap's source is
/// added, and it holds up every click on the Mac while it runs — which is why the work behind it is bounded
/// by `K.clickBudget` and every Accessibility element it touches by `K.axTimeout`.
@MainActor
public final class MouseTap {
    /// What the owner decided about one ⇧ Shift click.
    public enum Decision {
        /// Hand the event on: Finder does what it has always done.
        case pass
        /// ShiftPick has set the selection itself. The mouse-up that belongs to this press is swallowed
        /// too, or Finder would apply its own toggle to the item on release.
        case swallow
    }

    /// Why the system took the tap away. Two different defects: a **timeout** is this app holding the
    /// callback past the system's patience, which is a bug here; **user input** is the system deciding a
    /// tap had to be interrupted and is nobody's bug. One line that could not tell them apart sends a
    /// reader looking in the wrong place.
    public enum DisableReason: String, Sendable {
        case timeout, userInput
    }

    /// Read first, on every event. The Settings switch writes it, and it takes effect on the next click.
    public var isEnabled: () -> Bool = { true }
    /// Asked about a ⇧ Shift click, synchronously, with the event still held.
    public var onShiftClick: ((CGPoint, CGEventFlags) -> Decision)?
    /// Told about every other left click, and expected to return at once: the anchor is looked for after
    /// the click has been delivered, so an ordinary click gains no latency.
    public var onPlainClick: ((CGPoint, CGEventFlags) -> Void)?
    public var onDisabled: ((DisableReason, Int) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Set when a press was swallowed, cleared by the release it belongs to. Also cleared by the next
    /// press, so a release that never arrives cannot swallow somebody else's.
    private var swallowNextUp = false
    private var disableCount = 0

    public private(set) var isRunning = false

    public init() {}

    /// False when the tap could not be created, which is what a missing Accessibility permission looks
    /// like. The caller says so rather than going quiet.
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        let owner = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            // Not listen-only: swallowing the click is the whole point.
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<MouseTap>.fromOpaque(userInfo).takeUnretainedValue()
                return MainActor.assumeIsolated { tap.handle(type: type, event: event) }
            },
            userInfo: owner
        ) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        return true
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        swallowNextUp = false
        isRunning = false
    }

    /// The run loop owns the tap's source, and the callback recovers `self` from an unretained pointer, so
    /// a tap left running would outlive us and dereference freed memory.
    deinit {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The tap is re-enabled for us; the events it missed are gone, which is exactly the symptom
            // this has to make visible.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            swallowNextUp = false
            disableCount += 1
            onDisabled?(type == .tapDisabledByTimeout ? .timeout : .userInput, disableCount)
            return pass
        case .leftMouseDown:
            swallowNextUp = false
            guard isEnabled() else { return pass }
            let flags = event.flags
            // The first thing asked of every click, and the last thing asked of almost all of them.
            guard flags.contains(.maskShift) else {
                onPlainClick?(event.location, flags)
                return pass
            }
            // ⌥ Option and ⌃ Control mean something else in Finder. Neither is ours to take.
            guard !flags.contains(.maskAlternate), !flags.contains(.maskControl) else { return pass }
            guard onShiftClick?(event.location, flags) == .swallow else { return pass }
            swallowNextUp = true
            return nil
        case .leftMouseUp:
            guard swallowNextUp else { return pass }
            swallowNextUp = false
            return nil
        default:
            return pass
        }
    }
}
