import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os
import ShiftPickCore
import ShiftPickPlatform

/// What one ⇧ Shift click does, and where a range is measured from. **Every Accessibility call the feature
/// makes is made here, on `queue`, and nowhere else.**
///
/// The thread that serves the event taps never asks Accessibility anything: it hands a held click to this
/// worker through `DeadlineGate` and waits `K.clickBudget` for the answer. So this code may be as slow as a
/// hung Finder makes it without costing anybody a click: past the budget the click has already gone back to
/// the system, the ticket says so, and the work stops at the next thing it was about to ask.
///
/// **Every path fails safe.** A question Accessibility will not answer, a layout with no usable anchor, a
/// selection Finder refuses, a ticket nobody is waiting on any more: all of them end without a swallow, and
/// Finder does exactly what it has always done. The only way a click is swallowed is `ticket.finish(swallow:
/// true)`, which is one line, comes after the selection has been set, and is only honoured after a
/// `ticket.commit()` that was granted.
final class ShiftClickResolver: @unchecked Sendable {
    /// The two settings the click path reads, copied here so that it never reaches for the main actor.
    struct Options: Sendable {
        var enabled = true
        var commandShiftAdds = true
    }

    /// Where a range is measured from, per container. It is held as the two Accessibility elements, which
    /// compare by `CFEqual` across reads; when Finder has rebuilt them the anchor simply reads as gone, and
    /// the rule for a missing anchor takes over.
    private struct Anchor {
        let container: AXUIElement
        let item: AXUIElement
    }

    /// Serial, and the only place an Accessibility call is made from. The anchor and Finder's pid live on it
    /// and need no lock.
    let queue = DispatchQueue(label: "\(AppIdentity.bundleIdentifier).click.worker", qos: .userInteractive)

    /// An Accessibility call came back `apiDisabled`: the grant is gone, whatever the cached answer says.
    /// Called on `queue`.
    var onGrantLost: (() -> Void)?

    private let options = OSAllocatedUnfairLock(initialState: Options())
    private var anchor: Anchor?
    private var finderPID: pid_t?

    func update(_ settings: Settings) {
        options.withLock {
            $0 = Options(enabled: settings.enabled, commandShiftAdds: settings.commandShiftAdds)
        }
    }

    /// A launch, a grant that has just arrived, a Mac that has just woken: whatever was clicked before says
    /// nothing about what is selected now.
    func forgetAnchor() {
        queue.async { self.anchor = nil }
    }

    // MARK: - The anchor

    /// A plain or ⌘ Command click, already on its way to whoever it was for. Nothing is asked of anybody
    /// here: the hit test happens `K.anchorDelay` later and on the worker, so an ordinary click gains no
    /// latency at all, and the wait lets Finder finish selecting before it is asked what is under the pointer.
    func notePlainClick(at point: CGPoint) {
        guard options.withLock({ $0.enabled }) else { return }
        queue.asyncAfter(deadline: .now() + K.anchorDelay) { self.findAnchor(at: point) }
    }

    private func findAnchor(at point: CGPoint) {
        let refusals = AX.refusalCount
        defer { if AX.refusalCount != refusals { onGrantLost?() } }

        guard let pid = finderProcess() else { return }
        switch FinderAX.hit(at: point, finderPID: pid, timeout: Float(K.axTimeout)) {
        case .item(let target):
            // Only if the application that owns the view is in front by then. A click that went somewhere
            // else selected nothing in it, and the anchor must keep naming what is actually selected.
            let application = AXUIElementCreateApplication(AX.pid(of: target.view.container))
            AX.setTimeout(Float(K.axTimeout), on: application)
            guard FinderAX.isFrontmost(application) else { return }
            anchor = Anchor(container: target.view.container, item: target.item)
        case .emptyIconView:
            // The view has just deselected everything. Keeping the old anchor would let a later ⇧ Shift
            // click select a range from a file nothing on screen says anything about.
            anchor = nil
        case .elsewhere:
            break
        }
    }

    // MARK: - The click

    /// One ⇧ Shift click, with the event still held by the tap's thread. Runs on `queue`, called by
    /// `DeadlineGate`, and answers through `ticket` or not at all.
    func shiftClick(at point: CGPoint, flags: CGEventFlags, ticket: ClickTicket) {
        dispatchPrecondition(condition: .onQueue(queue))
        let refusals = AX.refusalCount
        defer { if AX.refusalCount != refusals { onGrantLost?() } }

        let options = self.options.withLock { $0 }
        guard options.enabled else { return }
        let adds = flags.contains(.maskCommand)
        // ⌘ Command with ⇧ Shift is Finder's when the switch is off, exactly as it is when ShiftPick is.
        guard !adds || options.commandShiftAdds else { return }
        guard let pid = finderProcess() else { return }

        let timeout = Float(K.axTimeout)
        let wanted = { !ticket.isAbandoned }
        guard case .item(let target) = FinderAX.hit(at: point, finderPID: pid, timeout: timeout,
                                                    shouldContinue: wanted)
        else { return }

        // The application that owns the view, which is Finder for a window and for the Desktop and
        // whichever application put the panel up for a panel.
        let application = AXUIElementCreateApplication(AX.pid(of: target.view.container))
        AX.setTimeout(timeout, on: application)
        // A name being typed in place: the click belongs to the text field, not to a range. Finder only:
        // a Save panel keeps its own name field focused the whole time it is up, so the same question
        // asked of a panel would refuse every click in it.
        if target.view.host != .panel, FinderAX.isRenaming(finder: application) { return }

        let pairs = FinderAX.items(in: target.view, timeout: timeout, shouldContinue: wanted)
        guard !pairs.isEmpty else { return pass("Finder answered too slowly, or with nothing") }
        let elements = pairs.map(\.1)
        guard let targetIndex = FinderAX.index(of: target.item, among: elements) else { return }

        let model = LayoutModel(items: pairs.map(\.0), fallbackFlow: target.view.fallbackFlow)

        // Read once: the derived anchor and ⌘ Command both want it, and it is a round trip to Finder.
        var selection: [Int]?
        func currentSelection() -> [Int] {
            if let selection { return selection }
            let read = FinderAX.selection(in: target.view, among: elements)
            selection = read
            return read
        }

        var anchorIndex: Int?
        if let anchor, CFEqual(anchor.container, target.view.container) {
            anchorIndex = FinderAX.index(of: anchor.item, among: elements)
        }
        if anchorIndex == nil {
            // Missing, stale, or in another container. The selection is what is left to measure from, and
            // a selection with nothing in it means there is nothing to measure at all.
            anchorIndex = model.derivedAnchor(target: targetIndex, selection: currentSelection())
        }
        guard let anchorIndex else { return pass("no anchor and nothing selected") }
        guard let range = model.range(from: anchorIndex, to: targetIndex)
        else { return pass("the anchor or the target is not a file") }
        let chosen = adds ? Array(Set(range).union(currentSelection())).sorted() : range

        // The point of no return, and it can be refused: a click that has already gone back to the system
        // is Finder's, and a selection set now would land on top of whatever Finder did with it.
        guard ticket.commit() else { return pass("the click took too long and was given back") }
        guard FinderAX.select(chosen.map { elements[$0] }, in: target.view) else {
            ticket.finish(swallow: false)
            return pass("Finder refused the selection")
        }
        ticket.finish(swallow: true)

        // The click was swallowed, so what it would otherwise have done has to be done here. Nobody is
        // waiting for this part: the press was answered the line above.
        FinderAX.raise(target.view, application: application)
        Log.click.debug("""
            selected \(chosen.count, privacy: .public) of \(elements.count, privacy: .public) \
            (\(String(describing: model.kind), privacy: .public)\(adds ? ", added" : "", privacy: .public))
            """)
        // The anchor does not move: widening and narrowing a range are both measured from the same file.
    }

    /// One place to say why a ⇧ Shift click was let through. Silence is a defect, and this is the only
    /// thing about the click path that is otherwise invisible; `debug` keeps it out of the way until
    /// somebody asks for it with `log stream --level debug`.
    private func pass(_ reason: StaticString) {
        Log.click.debug("let through: \(reason, privacy: .public)")
    }

    // MARK: - Finder

    /// Finder's pid, remembered until the process it names has gone or has become somebody else. Finder
    /// restarts, and a pid kept from the one before would make every click read as somebody else's.
    /// `NSRunningApplication` answers atomically from any thread.
    private func finderProcess() -> pid_t? {
        if let pid = finderPID,
           NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == FinderAX.bundleIdentifier {
            return pid
        }
        let found = NSRunningApplication.runningApplications(withBundleIdentifier: FinderAX.bundleIdentifier)
            .first?.processIdentifier
        finderPID = found
        return found
    }
}
