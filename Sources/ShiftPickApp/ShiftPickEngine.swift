import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import ShiftPickCore
import ShiftPickPlatform

/// The whole feature: one event tap, and what one ⇧ Shift click does.
///
/// **Every path through it fails safe.** A question Accessibility will not answer, a layout with no usable
/// anchor, a selection Finder refuses, the budget running out: all of them return the event unmodified, and
/// Finder does exactly what it has always done. The only way a click is swallowed is the last line of
/// `shiftClick`, after the new selection has already been set.
@MainActor
final class ShiftPickEngine: ObservableObject {
    /// Where a range is measured from, per container. It is held as the two Accessibility elements, which
    /// compare by `CFEqual` across reads; when Finder has rebuilt them the anchor simply reads as gone, and
    /// the rule for a missing anchor takes over.
    private struct Anchor {
        let container: AXUIElement
        let item: AXUIElement
    }

    /// Whether the tap is up. False while the Accessibility permission is missing, and false when macOS
    /// refused the tap, which the System page tells the two apart by asking `tapWasRefused`.
    @Published private(set) var isWatching = false
    /// The tap could not be created although the permission is granted. It is the one failure that is
    /// otherwise completely silent.
    @Published private(set) var tapWasRefused = false
    /// How many times the system has taken the tap away this launch, both reasons together.
    @Published private(set) var tapDisableCount = 0

    private let tap = MouseTap()
    private let store: SettingsStore
    private var anchor: Anchor?
    private var finderPID: pid_t?
    private var cancellables: Set<AnyCancellable> = []

    init(store: SettingsStore) {
        self.store = store
        tap.isEnabled = { [weak self] in self?.store.settings.enabled ?? false }
        tap.onShiftClick = { [weak self] point, flags in
            self?.shiftClick(at: point, flags: flags) ?? .pass
        }
        tap.onPlainClick = { [weak self] point, _ in self?.notePlainClick(at: point) }
        tap.onDisabled = { [weak self] reason, count in
            self?.tapDisableCount = count
            switch reason {
            case .timeout:
                Log.click.error("the event tap was disabled by TIMEOUT (\(count, privacy: .public) this launch) and re-enabled; clicks were lost")
            case .userInput:
                Log.click.error("the event tap was disabled by USER INPUT (\(count, privacy: .public) this launch) and re-enabled; clicks were lost")
            }
        }
        // The kill switch is the tap's own flag, so turning ShiftPick off takes effect on the next click
        // rather than on the next launch. The tap stays up: tearing it down and building it again on a
        // switch is how a tap ends up refused.
        store.$settings
            .map(\.enabled)
            .removeDuplicates()
            .sink { on in Log.app.notice("ShiftPick \(on ? "enabled" : "disabled", privacy: .public)") }
            .store(in: &cancellables)
    }

    // MARK: - Running

    /// Starts the tap. False when macOS refused it, which is what a permission that has just been taken
    /// away looks like; the caller says so rather than going quiet.
    @discardableResult
    func start() -> Bool {
        guard !isWatching else { return true }
        guard tap.start() else {
            tapWasRefused = true
            isWatching = false
            Log.app.error("the event tap could not be created; is Accessibility granted?")
            return false
        }
        tapWasRefused = false
        isWatching = true
        anchor = nil
        Log.app.notice("watching for clicks")
        return true
    }

    func stop() {
        guard isWatching || tapWasRefused else { return }
        tap.stop()
        isWatching = false
        tapWasRefused = false
        anchor = nil
        Log.app.notice("stopped watching for clicks")
    }

    // MARK: - The anchor

    /// A plain or ⌘ Command click. Nothing is asked of Finder here: the event has already been handed back
    /// to the system, and the hit test happens a moment later, so an ordinary click gains no latency at all.
    private func notePlainClick(at point: CGPoint) {
        DispatchQueue.main.asyncAfter(deadline: .now() + K.anchorDelay) { [weak self] in
            MainActor.assumeIsolated { self?.findAnchor(at: point) }
        }
    }

    private func findAnchor(at point: CGPoint) {
        guard let pid = finderProcess() else { return }
        switch FinderAX.hit(at: point, finderPID: pid, timeout: Float(K.axTimeout)) {
        case .item(let target):
            // Only if the application that owns the view is frontmost by then. A click that went
            // somewhere else selected nothing in it, and the anchor must keep naming what is actually
            // selected.
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == AX.pid(of: target.view.container) else { return }
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

    private func shiftClick(at point: CGPoint, flags: CGEventFlags) -> MouseTap.Decision {
        let deadline = Date().addingTimeInterval(K.clickBudget)
        let adds = flags.contains(.maskCommand)
        // ⌘ Command with ⇧ Shift is Finder's when the switch is off, exactly as it is when ShiftPick is.
        guard !adds || store.settings.commandShiftAdds else { return .pass }
        guard let pid = finderProcess() else { return .pass }

        let timeout = Float(K.axTimeout)
        guard case .item(let target) = FinderAX.hit(at: point, finderPID: pid, timeout: timeout)
        else { return .pass }

        // The application that owns the view, which is Finder for a window and for the Desktop and
        // whichever application put the panel up for a panel.
        let application = AXUIElementCreateApplication(AX.pid(of: target.view.container))
        AX.setTimeout(timeout, on: application)
        // A name being typed in place: the click belongs to the text field, not to a range. Finder only:
        // a Save panel keeps its own name field focused the whole time it is up, so the same question
        // asked of a panel would refuse every click in it.
        if target.view.host != .panel, FinderAX.isRenaming(finder: application) { return .pass }

        let pairs = FinderAX.items(in: target.view, timeout: timeout)
        guard !pairs.isEmpty, Date() < deadline else { return pass("Finder answered too slowly") }
        let elements = pairs.map(\.1)
        guard let targetIndex = FinderAX.index(of: target.item, among: elements) else { return .pass }

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
        guard Date() < deadline else { return pass("the click took too long") }

        let chosen = adds ? Array(Set(range).union(currentSelection())).sorted() : range
        guard FinderAX.select(chosen.map { elements[$0] }, in: target.view)
        else { return pass("Finder refused the selection") }

        // The click was swallowed, so what it would otherwise have done has to be done here.
        FinderAX.raise(target.view, application: application)
        Log.click.debug("""
            selected \(chosen.count, privacy: .public) of \(elements.count, privacy: .public) \
            (\(String(describing: model.kind), privacy: .public)\(adds ? ", added" : "", privacy: .public))
            """)
        // The anchor does not move: widening and narrowing a range are both measured from the same file.
        return .swallow
    }

    /// One place to say why a ⇧ Shift click was let through. Silence is a defect, and this is the only
    /// thing about the click path that is otherwise invisible; `debug` keeps it out of the way until
    /// somebody asks for it with `log stream --level debug`.
    private func pass(_ reason: StaticString) -> MouseTap.Decision {
        Log.click.debug("let through: \(reason, privacy: .public)")
        return .pass
    }

    // MARK: - Finder

    /// Finder's pid, remembered until the process it names has gone. Finder restarts, and a pid kept from
    /// the one before would make every click read as somebody else's.
    private func finderProcess() -> pid_t? {
        if let pid = finderPID, NSRunningApplication(processIdentifier: pid) != nil { return pid }
        let found = NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == FinderAX.bundleIdentifier }?
            .processIdentifier
        finderPID = found
        return found
    }
}
