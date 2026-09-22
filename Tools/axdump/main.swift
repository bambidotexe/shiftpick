import ApplicationServices
import AppKit
import CoreGraphics
import Foundation
import ShiftPickCore
import ShiftPickPlatform

/// The development probe. **It never ships**: `scripts/make-app.sh` copies one executable into the bundle
/// and this is not it.
///
/// It exists because Finder's Accessibility hierarchy is not documented and not guessable, and because a
/// command-line tool inherits the Accessibility grant of the terminal that starts it, so it can read that
/// hierarchy long before the app itself is allowed to. Everything `FinderAX` claims about Finder was read
/// with this, and `docs/macOS.md` holds the dumps.
///
/// ```sh
/// swift run axdump trust            # is this terminal allowed to ask at all
/// swift run axdump views            # every icon view Finder is showing, and its items
/// swift run axdump at <x> <y>       # what is under a point, and the chain above it
/// swift run axdump range <x> <y> [ax ay]   # what a ⇧ Shift click there would select, without clicking
/// swift run axdump tree [depth]     # Finder's whole tree, roles and frames
/// ```
enum AXDump {
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count > 1 else { usage(); exit(1) }
        guard arguments[1] == "trust" || AXIsProcessTrusted() else {
            print("This terminal is not trusted for Accessibility, so Finder will answer nothing.")
            print("System Settings > Privacy & Security > Accessibility, and add the terminal.")
            exit(1)
        }
        switch arguments[1] {
        case "trust":
            print("Accessibility: \(AXIsProcessTrusted() ? "granted" : "not granted") for this process")
        case "views":
            views()
        case "at":
            guard arguments.count >= 4, let x = Double(arguments[2]), let y = Double(arguments[3])
            else { usage(); exit(1) }
            at(CGPoint(x: x, y: y))
        case "range":
            guard arguments.count >= 4, let x = Double(arguments[2]), let y = Double(arguments[3])
            else { usage(); exit(1) }
            var anchorPoint: CGPoint?
            if arguments.count >= 6, let ax = Double(arguments[4]), let ay = Double(arguments[5]) {
                anchorPoint = CGPoint(x: ax, y: ay)
            }
            range(CGPoint(x: x, y: y), anchorPoint: anchorPoint)
        case "tree":
            tree(depth: arguments.count >= 3 ? Int(arguments[2]) ?? 4 : 4)
        default:
            usage(); exit(1)
        }
    }

    static func usage() {
        print("""
        usage: axdump <command>
          trust             whether this process may ask Accessibility anything
          views             every Finder icon view on screen, with its items in AX order
          at <x> <y>        what is under a point, and every element above it
          range <x> <y> [ax ay]   what a Shift-click there would select, measured from the icon at ax ay or from what is selected
          tree [depth]      Finder's whole element tree
        """)
    }

    // MARK: - Commands

    static func finderPID() -> pid_t {
        guard let pid = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == FinderAX.bundleIdentifier })?.processIdentifier
        else {
            print("Finder is not running.")
            exit(1)
        }
        return pid
    }

    static func views() {
        let app = AXUIElementCreateApplication(finderPID())
        AX.setTimeout(5, on: app)
        var found: [(String, FinderAX.IconView)] = []
        collect(app, depth: 0, into: &found)
        guard !found.isEmpty else { print("no icon view is on screen"); return }
        for (name, view) in found {
            let items = FinderAX.items(in: view, timeout: 5)
            let model = LayoutModel(items: items.map(\.0), fallbackFlow: view.fallbackFlow)
            let selected = Set(FinderAX.selection(in: view, among: items.map(\.1)).indices)
            print("== \(name): \(items.count) items, \(model.kind), fallback \(view.fallbackFlow.rawValue)")
            for (index, pair) in items.enumerated() {
                let frame = pair.0.frame
                print(String(format: "   [%3d] place %4d  section %d  ax %3d  (%.0f,%.0f %.0fx%.0f)%@%@",
                             index, model.readingPosition(of: index) ?? -1, pair.0.section, pair.0.axOrder,
                             frame.minX, frame.minY, frame.width, frame.height,
                             selected.contains(index) ? "  selected" : "",
                             pair.0.isFile ? "" : "  STACK"))
            }
        }
    }

    static func collect(_ element: AXUIElement, depth: Int, into found: inout [(String, FinderAX.IconView)]) {
        guard depth < 12 else { return }
        let role = AX.role(element)
        let subrole = AX.subrole(element)
        if role == "AXGroup", subrole == "AXDesktop" {
            found.append(("desktop", FinderAX.IconView(container: element, window: nil, host: .desktop)))
            return
        }
        if role == "AXList", subrole == "AXCollectionList" {
            let window = AX.element(element, "AXWindow")
            let title = window.flatMap { AX.string($0, kAXTitleAttribute as String) } ?? "window"
            let identifier = window.flatMap { AX.string($0, "AXIdentifier") } ?? ""
            let host: FinderAX.Host = identifier.hasSuffix("-panel") ? .panel : .finderWindow
            found.append((title, FinderAX.IconView(container: element, window: window, host: host)))
            return
        }
        for child in AX.children(element) { collect(child, depth: depth + 1, into: &found) }
    }

    static func at(_ point: CGPoint) {
        let pid = finderPID()
        switch FinderAX.hit(at: point, finderPID: pid, timeout: 5) {
        case .item(let target):
            print("item in \(target.view.host)")
            print("  \(describe(target.item))")
            print("  container \(describe(target.view.container))")
        case .emptyIconView:
            print("an icon view, but not an item")
        case .elsewhere:
            print("not a Finder icon view")
        }
        guard let hit = AX.element(at: point, timeout: 5) else { print("nothing answered"); return }
        var element: AXUIElement? = hit
        var level = 0
        while let current = element, level < 10 {
            print(String(repeating: "  ", count: level) + describe(current))
            element = AX.parent(current)
            level += 1
        }
    }

    /// What a ⇧ Shift click at this point would select, worked out exactly as the app works it out and
    /// printed rather than applied. With no anchor point the stored anchor reads as gone, which is what a
    /// fresh launch sees: a stand-in is named from the selection.
    static func range(_ point: CGPoint, anchorPoint: CGPoint?) {
        let pid = finderPID()
        guard case .item(let target) = FinderAX.hit(at: point, finderPID: pid, timeout: 5) else {
            print("not an item: the click would be let through")
            return
        }
        let items = FinderAX.items(in: target.view, timeout: 5)
        let elements = items.map(\.1)
        guard let targetIndex = FinderAX.index(of: target.item, among: elements) else {
            print("the item is not among the ones the view lists")
            return
        }
        let model = LayoutModel(items: items.map(\.0), fallbackFlow: target.view.fallbackFlow)
        let reading = FinderAX.selection(in: target.view, among: elements)
        print("layout: \(model.kind); \(items.count) items; \(reading.indices.count) selected on screen, "
              + "\(reading.unmapped.count) selected elsewhere")

        var stored: Int?
        if let anchorPoint,
           case .item(let anchorHit) = FinderAX.hit(at: anchorPoint, finderPID: pid, timeout: 5),
           CFEqual(anchorHit.view.container, target.view.container) {
            stored = FinderAX.index(of: anchorHit.item, among: elements)
        }
        var from = model.effectiveAnchor(stored: stored, selection: reading.indices)
        if from == nil {
            let scrolled = FinderAX.isScrolled(target.view)
            guard scrolled == false, let first = model.firstItem else {
                print("nothing selected and the view is scrolled or unreadable: the click would be let through")
                return
            }
            print("nothing selected; the view is not scrolled, so the first icon stands in")
            from = first
        }
        guard let from,
              let outcome = model.shiftClick(from: from, selection: reading.indices, target: targetIndex) else {
            print("the anchor or the target is not a file: the click would be let through")
            return
        }
        let how = stored == from ? "the anchor" : "a stand-in"
        let shape = if case .band = outcome.shape { "the rubber band" } else { "a slice of the reading order" }
        print("measured from item \(from) (\(how)) to \(targetIndex), \(shape): "
              + "\(outcome.shape.items.count) in the range, \(outcome.selection.count) selected afterwards")
        for index in outcome.selection {
            let name = AX.string(elements[index], "AXIdentifier")
                ?? AX.string(elements[index], kAXTitleAttribute as String) ?? "?"
            let place = model.readingPosition(of: index).map(String.init) ?? "-"
            print("  [\(place)] \(name)\(outcome.shape.items.contains(index) ? "" : "   (kept)")")
        }
    }

    static func tree(depth limit: Int) {
        let app = AXUIElementCreateApplication(finderPID())
        AX.setTimeout(5, on: app)
        walk(app, depth: 0, limit: limit)
    }

    static func walk(_ element: AXUIElement, depth: Int, limit: Int) {
        print(String(repeating: "  ", count: depth) + describe(element))
        guard depth < limit else { return }
        for child in AX.children(element) { walk(child, depth: depth + 1, limit: limit) }
    }

    static func describe(_ element: AXUIElement) -> String {
        var text = "\(AX.role(element) ?? "?")/\(AX.subrole(element) ?? "-")"
        if let title = AX.string(element, kAXTitleAttribute as String), !title.isEmpty {
            text += " title=\(title.prefix(40))"
        }
        if let identifier = AX.string(element, "AXIdentifier"), !identifier.isEmpty {
            text += " id=\(identifier)"
        }
        if let frame = AX.frame(element) {
            text += String(format: " (%.0f,%.0f %.0fx%.0f)", frame.minX, frame.minY, frame.width, frame.height)
        }
        if AX.url(element) != nil { text += " url" }
        let children = AX.children(element).count
        if children > 0 { text += " kids=\(children)" }
        return text
    }
}

AXDump.main()
