import AppKit
import Combine
import ShiftPickCore
import ShiftPickPlatform

/// The menu-bar item and its menu. The menu is rebuilt from scratch on every open, so it is never a
/// language or a state behind, and the item's visibility follows the one setting that owns it.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    weak var engine: ShiftPickEngine?
    var store: SettingsStore?
    var openSettings: (() -> Void)?

    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []

    func setup() {
        guard let store else { return }
        apply(visible: store.settings.showInMenuBar)
        store.$settings
            .map(\.showInMenuBar)
            .removeDuplicates()
            .sink { [weak self] visible in MainActor.assumeIsolated { self?.apply(visible: visible) } }
            .store(in: &cancellables)
    }

    /// Releasing the item back to `NSStatusBar.system` is the whole of hiding it: an item merely hidden
    /// keeps its slot, and the icons to its left would not close up. Logged, because a hidden item is an
    /// app with no visible trace and the log is then the only place that says it is running on purpose.
    private func apply(visible: Bool) {
        if visible {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = Self.icon()
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        } else {
            guard let item = statusItem else { return }
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        Log.app.notice("menu bar item \(visible ? "shown" : "hidden", privacy: .public)")
    }

    // MARK: - The menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let words = Loc.menu

        let login = NSMenuItem(title: words.launchAtLogin, action: #selector(toggleLaunchAtLogin),
                               keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        // One read-only line: what the app is doing right now, and nothing else.
        let status = NSMenuItem(title: statusLine(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: words.settings, action: #selector(openSettingsItem),
                                  keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: words.quit, action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApplication.shared
        menu.addItem(quit)
    }

    private func statusLine() -> String {
        let words = Loc.menu
        // The same rule as every window: the engine has asked a live question about the grant, and
        // `accessibilityGranted` can go on saying yes after the grant has gone.
        let status = engine?.status ?? .stopped
        if !status.showsGrant(systemSays: Permissions.accessibilityGranted) {
            return words.statusNeedsPermission
        }
        if engine?.tapWasRefused == true { return words.statusNoTap }
        if engine?.breakerIsOpen == true { return words.statusStoppedByMacOS }
        return engine?.isWatching == true ? words.statusWatching : words.statusNoTap
    }

    /// The system's answer is what the menu shows next time, so nothing is mirrored here. A refusal is
    /// logged rather than swallowed; the Settings window is where it gets a sentence.
    @objc private func toggleLaunchAtLogin() {
        do { try LoginItem.setEnabled(!LoginItem.isEnabled) }
        catch { Log.app.error("launch at login could not be changed: \(error.localizedDescription, privacy: .public)") }
    }

    @objc private func openSettingsItem() { openSettings?() }

    // MARK: - The mark

    /// The brand mark, drawn rather than shipped as an asset so that it rebuilds from source and follows
    /// the menu bar's own colour as a template image. It is the app icon's drawing on an 18 pt canvas.
    ///
    /// Four icons in a grid, three of them selected and the fourth not: a range picked out of a folder.
    /// The numbers are the menu-bar SVG's, in its own top-left coordinates, which is why the image is
    /// flipped. The fourth tile is a ring: its hole is a second tile inside it, cut out by the even-odd rule.
    static func icon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let path = NSBezierPath()
            path.windingRule = .evenOdd
            for origin in [NSPoint(x: 1, y: 1), NSPoint(x: 10, y: 1), NSPoint(x: 1, y: 10), NSPoint(x: 10, y: 10)] {
                appendTile(to: path, in: NSRect(origin: origin, size: NSSize(width: 7, height: 7)), radius: 1.566)
            }
            appendTile(to: path, in: NSRect(x: 11.5, y: 11.5, width: 4, height: 4), radius: 0.2)
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = AppIdentity.name
        return image
    }

    /// One rounded square with the SVG's continuous corners: each corner leaves its edge 1.6 radii before
    /// the corner, eases in, turns through the middle 36° of a circle of `radius` and eases out. That arc
    /// is written as one cubic, which is within a millionth of the radius of the circle.
    private static func appendTile(to path: NSBezierPath, in rect: NSRect, radius: CGFloat) {
        // One corner, in radii from the corner itself: the first number runs along the edge coming in, the
        // second along the edge going out. Three points to a curve: two controls, then where it ends.
        let corner: [(CGFloat, CGFloat)] = [
            (-1.0396, 0), (-0.760, 0), (-0.546, 0.109),
            (-0.358, 0.205), (-0.205, 0.358), (-0.109, 0.546),
            (0, 0.760), (0, 1.0396), (0, 1.5996),
        ]
        // Clockwise on screen, starting along the top edge: each corner, the way in and the way out.
        let turns: [(NSPoint, CGVector, CGVector)] = [
            (NSPoint(x: rect.maxX, y: rect.minY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1)),
            (NSPoint(x: rect.maxX, y: rect.maxY), CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 0)),
            (NSPoint(x: rect.minX, y: rect.maxY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1)),
            (NSPoint(x: rect.minX, y: rect.minY), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: 0)),
        ]
        for (index, (point, incoming, outgoing)) in turns.enumerated() {
            func at(_ offset: (CGFloat, CGFloat)) -> NSPoint {
                NSPoint(x: point.x + (offset.0 * incoming.dx + offset.1 * outgoing.dx) * radius,
                        y: point.y + (offset.0 * incoming.dy + offset.1 * outgoing.dy) * radius)
            }
            let start = at((-1.5996, 0))
            if index == 0 { path.move(to: start) } else { path.line(to: start) }
            for curve in stride(from: 0, to: corner.count, by: 3) {
                path.curve(to: at(corner[curve + 2]),
                           controlPoint1: at(corner[curve]), controlPoint2: at(corner[curve + 1]))
            }
        }
        path.close()
    }
}
