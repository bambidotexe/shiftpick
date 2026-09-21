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

        let enable = NSMenuItem(title: words.enable, action: #selector(toggleEnabled), keyEquivalent: "")
        enable.target = self
        enable.state = store?.settings.enabled == true ? .on : .off
        menu.addItem(enable)
        menu.addItem(.separator())

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
        if !Permissions.accessibilityGranted { return words.statusNeedsPermission }
        if engine?.tapWasRefused == true { return words.statusNoTap }
        if store?.settings.enabled != true { return words.statusOff }
        return engine?.isWatching == true ? words.statusWatching : words.statusNoTap
    }

    @objc private func toggleEnabled() {
        guard let store else { return }
        store.settings.enabled.toggle()
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
    /// the menu bar's own colour as a template image.
    ///
    /// A column of three bars: the first and the third are outlines and the middle one is filled, which is
    /// the gesture in one picture — two clicks, and everything between them taken. The numbers below are
    /// the only ones that fit an 18 pt canvas with equal gaps above, below and between: three bars of
    /// `barHeight` and two gaps of `gap` fill exactly the inset height.
    static func icon() -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let width: CGFloat = 13
            let barHeight: CGFloat = 3.4
            let gap: CGFloat = 1.9
            let stroke: CGFloat = 1.1
            let total = barHeight * 3 + gap * 2
            let left = (side - width) / 2
            var top = (side + total) / 2 - barHeight

            NSColor.black.setFill()
            NSColor.black.setStroke()
            for index in 0..<3 {
                let rect = NSRect(x: left, y: top, width: width, height: barHeight)
                let path = NSBezierPath(roundedRect: index == 1 ? rect : rect.insetBy(dx: stroke / 2, dy: stroke / 2),
                                        xRadius: barHeight / 2, yRadius: barHeight / 2)
                if index == 1 {
                    path.fill()
                } else {
                    path.lineWidth = stroke
                    path.stroke()
                }
                top -= barHeight + gap
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = AppIdentity.name
        return image
    }
}
