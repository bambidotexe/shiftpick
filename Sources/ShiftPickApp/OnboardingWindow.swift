import AppKit
import ShiftPickCore
import ShiftPickPlatform

/// The first-run wizard, from `~/Projects/macos-app-template/template/Sources/ExemplarApp/OnboardingWindow.swift`. Read
/// that skill whole before changing anything here: most of it is traps, and every one of them shipped once.
///
/// Four pages: the pitch, the one permission the app cannot work without, where the app lives, and
/// "All set".
///
/// **An ordinary window.** The normal level, the default collection behaviour, the same as `SettingsWindow`
/// and `UpdateWindow`. It comes up in front because it is the last window to open, and from then on it takes
/// its turn like any other: the Accessibility dialog and System Settings both open over it and stay there
/// until the user leaves them. It belongs to the Space it opened in and keeps its place in it across a Space
/// switch. The app is activated once, when the window opens, and never again from here.
///
/// **Two things bring it back**, both of them a flow ending, and nothing else: `GrantItem.returnsFocus` for a
/// flow that owned a dialog of the app's own, and `GrantItem.mayOpen` for a flow that sent the user to
/// another app, through `FocusReturnWatch`.
///
/// **No permission prompt is ever shown unless the user clicked for it.** Nothing in this window, and
/// nothing in the app's start-up path, calls a request API; only a row's button does.
///
/// **Nothing tells an app that a grant was made in System Settings**, so a list page re-reads its rows every
/// `K.onboardingPollInterval` while the window is up. That poll is the app's only one: its tick also tells
/// the app, through `grantMayHaveChanged`, so the engine starts the moment the permission arrives. A page is
/// built only on a change of step; a row that moves redraws its own trailing control and nothing else.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    /// Whether another window of the app still needs it active once the wizard goes away. Injected, as
    /// `SettingsWindow`'s is: an accessory app with no window left is still the active application, which
    /// would send the user's keystrokes nowhere.
    var othersNeedUsActive: @MainActor () -> Bool = { false }

    private let pages: [OnboardingPage]
    /// Pressed on the last page: the flag that keeps the wizard from opening again is recorded there.
    private let onFinish: () -> Void
    /// Called on every poll tick and whenever a row's flow ends, so the app can start or stop the engine
    /// without a timer of its own.
    private let grantMayHaveChanged: () -> Void

    /// The app icon's own blue (`Resources/AppIcon.icon/icon.json`), used to accent one word of the headline
    /// and to tint the capsules.
    private static let brand = NSColor(srgbRed: 0.22353, green: 0.47059, blue: 0.96078, alpha: 1)

    private var step = 0
    private var observers: [NSObjectProtocol] = []
    /// The rows of the page on screen, by row. A row that moves updates itself and nothing else: rebuilding
    /// the page to show it blanks the window and draws it again, which reads as a blink.
    private var rows: [GrantID: GrantRow] = [:]
    /// The page's stepping button, whose title follows whether the page's rule is met. Weak: the page that
    /// owns it is thrown away on a change of step.
    private weak var primaryButton: NSButton?
    private var poll: Timer?
    /// Brings the wizard back when the app a row's button sent the user to quits.
    private let focusReturn = FocusReturnWatch()

    init(pages: [OnboardingPage], onFinish: @escaping () -> Void,
         grantMayHaveChanged: @escaping () -> Void) {
        self.pages = pages
        self.onFinish = onFinish
        self.grantMayHaveChanged = grantMayHaveChanged
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: OnboardingMetrics.windowWidth,
                                            height: OnboardingMetrics.heroHeight),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = AppIdentity.name
        w.center()
        w.isReleasedWhenClosed = false
        // Nothing else. No `level`, and no `collectionBehavior`: both are what make this window misbehave.
        w.contentView = NSView()
        super.init(window: w)
        w.delegate = self
        // Coming back from System Settings: re-read the rows. The poll covers a window that is already key
        // and so never sees this edge.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshGrants() }
            })
        // The app coming forward brings the wizard with it, the way any app's window does.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.comeForward() }
            })
        render()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        poll?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    var isUp: Bool { window?.isVisible == true }

    /// The one unconditional activation in the feature. An accessory app is not brought forward by the
    /// cooperative `activate()`, and this is the window that most needs to be seen.
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        startPolling()
    }

    /// The wizard back in front of the app's own windows, and only while it is the app's one window, so it
    /// never lands on top of Settings or the update window. Ordering front, never
    /// `NSApp.activate(ignoringOtherApps:)`: that is what pulls a wizard over the System Settings window it
    /// has just opened.
    private func comeForward() {
        guard let window, window.isVisible, !othersNeedUsActive() else { return }
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        stopPolling()
        focusReturn.stop()
        if !othersNeedUsActive() { NSApp.deactivate() }
    }

    // MARK: - Building a page

    /// Builds the page for `step`. Called on a change of step and nowhere else: a grant that moves, a flow
    /// that starts or ends, and a poll tick all change one row, never the page.
    private func render() {
        guard let window, let content = window.contentView, pages.indices.contains(step) else { return }
        rows.removeAll()
        primaryButton = nil
        content.subviews.forEach { $0.removeFromSuperview() }

        let page = pages[step]
        let view: NSView
        switch page {
        case let .hero(title, accent, body, pills, button):
            view = hero(title: title, accent: accent, body: body, pills: pills, button: button)
        case let .list(header, intro, items, advanceWhen, _):
            view = listPage(header: header, intro: intro, items: items, advanceWhen: advanceWhen)
        case let .final(title, body, button):
            view = hero(title: title, accent: nil, body: body, pills: [], button: button)
        }

        // Grow downward from a fixed title bar.
        var frame = window.frame
        let dy = page.height - content.frame.height
        frame.origin.y -= dy
        frame.size.height += dy
        window.setFrame(frame, display: true, animate: window.isVisible)

        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.topAnchor.constraint(equalTo: content.topAnchor),
            view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        reportButtonGeometry("on render")
    }

    private func hero(title: String, accent: String?, body: String, pills: [Pill],
                      button: String) -> NSView {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.heightAnchor.constraint(equalToConstant: OnboardingMetrics.heroIcon).isActive = true

        let headline = NSTextField(wrappingLabelWithString: "")
        // A selectable label enters the field editor on a click and loses its attributes.
        headline.isSelectable = false
        headline.allowsEditingTextAttributes = true
        headline.font = .systemFont(ofSize: OnboardingMetrics.heroTitle, weight: .bold)
        headline.alignment = .center
        headline.attributedStringValue = Self.accented(title, word: accent)
        headline.preferredMaxLayoutWidth = OnboardingMetrics.heroTextWidth
        headline.widthAnchor
            .constraint(lessThanOrEqualToConstant: OnboardingMetrics.heroTextWidth).isActive = true

        let description = NSTextField(wrappingLabelWithString: body)
        description.isSelectable = false
        description.font = .systemFont(ofSize: OnboardingMetrics.heroBody)
        description.alignment = .center
        description.preferredMaxLayoutWidth = OnboardingMetrics.heroTextWidth
        description.textColor = .secondaryLabelColor

        var extras: [NSView] = []
        if !pills.isEmpty {
            let row = NSStackView()
            row.spacing = 8
            pills.forEach { row.addArrangedSubview(Self.pill($0)) }
            row.widthAnchor
                .constraint(lessThanOrEqualToConstant: OnboardingMetrics.pillRowWidth).isActive = true
            extras = [row]
        }

        let next = NSButton(title: button, target: nil, action: nil)
        next.bezelStyle = .rounded
        next.keyEquivalent = "\r"
        next.actionHandler = { [weak self] in self?.advance() }

        let stack = NSStackView(views: [icon, headline, description] + extras + [next])
        stack.orientation = .vertical
        stack.spacing = OnboardingMetrics.heroSpacing
        stack.setCustomSpacing(OnboardingMetrics.heroTitleToBody, after: headline)
        stack.edgeInsets = OnboardingMetrics.heroInsets
        return stack
    }

    private func listPage(header: String, intro: String, items: [GrantItem],
                          advanceWhen: @escaping ([GrantItem]) -> Bool) -> NSView {
        let headerLabel = NSTextField(labelWithString: header)
        headerLabel.font = .systemFont(ofSize: OnboardingMetrics.listTitle, weight: .bold)
        let introLabel = NSTextField(wrappingLabelWithString: intro)
        introLabel.font = .systemFont(ofSize: OnboardingMetrics.listIntro)
        introLabel.textColor = .secondaryLabelColor
        introLabel.preferredMaxLayoutWidth = OnboardingMetrics.listIntroWidth

        let list = NSStackView()
        list.orientation = .vertical
        list.spacing = OnboardingMetrics.listRowSpacing
        list.alignment = .leading
        for (i, item) in items.enumerated() {
            if i > 0 {
                let separator = NSBox()
                separator.boxType = .separator
                list.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
            }
            let row = GrantRow(item: item,
                               window: { [weak self] in self?.window },
                               focusReturn: focusReturn,
                               didFinish: { [weak self] in
                                   self?.updatePrimaryButton()
                                   self?.grantMayHaveChanged()
                               })
            rows[item.id] = row
            list.addArrangedSubview(row.view)
        }
        list.arrangedSubviews.forEach { $0.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true }

        let primary = NSButton(title: "", target: nil, action: nil)
        primary.bezelStyle = .rounded
        primary.keyEquivalent = "\r"
        primary.actionHandler = { [weak self] in self?.advance() }
        primaryButton = primary

        // The footer is a plain view with the button pinned to its trailing edge and to **both** its top
        // and bottom, which is what fixes the footer's height to the button's.
        //
        // An `NSStackView` holding an invisible spacer is the trap: a spacer has no intrinsic height, so
        // nothing decides the footer's own height, and the vertical stack hands it every point of slack the
        // page is not using. Granting a permission swaps that row's 26 pt button for an 18 pt "Granted"
        // label; the list shrinks, the footer grows to absorb it, and the button sits wherever the slack
        // put it rather than at the bottom of the page. It is still drawn, `AXFrame` still names a plausible
        // rectangle, no constraint breaks, and a press on it does not land.
        let footer = NSView()
        primary.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(primary)
        NSLayoutConstraint.activate([
            primary.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            primary.topAnchor.constraint(equalTo: footer.topAnchor),
            primary.bottomAnchor.constraint(equalTo: footer.bottomAnchor),
        ])

        // The slack goes here, deliberately, and into nothing else: above the footer, so the stepping button
        // stays at the bottom right of the page however tall the rows happen to be.
        let slack = NSView()
        slack.setContentHuggingPriority(.init(1), for: .vertical)
        slack.setContentCompressionResistancePriority(.init(1), for: .vertical)

        let stack = NSStackView(views: [headerLabel, introLabel, list, slack, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = OnboardingMetrics.listSpacing
        stack.setCustomSpacing(OnboardingMetrics.listIntroToList, after: introLabel)
        stack.setCustomSpacing(OnboardingMetrics.listToFooter, after: list)
        stack.edgeInsets = OnboardingMetrics.listInsets
        // Width constraints only once every view shares the stack as an ancestor.
        list.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                    constant: -OnboardingMetrics.listSideInset).isActive = true
        footer.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        updatePrimaryButton()
        return stack
    }

    /// *Continue* once the page's rule is met, *Skip* until then. Set in place, so the page is never rebuilt
    /// for a word.
    private func updatePrimaryButton() {
        guard let primaryButton, pages.indices.contains(step),
              case let .list(_, _, items, advanceWhen, _) = pages[step] else { return }
        let words = Loc.onboarding
        let title = advanceWhen(items) ? words.continueButton : words.skipButton
        guard primaryButton.title != title else { return }
        Log.onboarding.info("stepping button on page \(self.step, privacy: .public) now reads \(title, privacy: .public)")
        primaryButton.title = title
    }

    /// Where the stepping button actually is once the page has settled, and whether every view between it
    /// and the window still contains it. A button drawn in one place and hit-tested in another is what a
    /// ballooning footer looks like from the outside, and this is the line that shows it.
    private func reportButtonGeometry(_ when: String) {
        guard let primaryButton, let content = window?.contentView else { return }
        content.layoutSubtreeIfNeeded()
        var chain = ""
        var view: NSView = primaryButton
        while let parent = view.superview {
            let contains = parent.bounds.contains(view.frame) ? "" : " DOES NOT CONTAIN"
            chain += " \(type(of: parent))(\(parent.bounds.height)\(contains))"
            view = parent
            if parent == content { break }
        }
        let inWindow = primaryButton.convert(primaryButton.bounds, to: nil)
        Log.onboarding.debug("\(when, privacy: .public): button \(String(describing: inWindow), privacy: .public) chain:\(chain, privacy: .public)")
    }

    // MARK: - Following the system

    /// Re-reads every row and lets each one redraw itself if its own state moved, then tells the app, which
    /// is how the engine starts without a second timer. A page with no rows (the pitch, "All set") still
    /// reports: the permission can arrive while either is on screen.
    private func refreshGrants() {
        for row in rows.values { row.refresh() }
        updatePrimaryButton()
        reportButtonGeometry("after a poll tick")
        grantMayHaveChanged()
    }

    /// Idempotent.
    private func startPolling() {
        guard poll == nil else { return }
        poll = Timer.scheduledTimer(withTimeInterval: K.onboardingPollInterval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.refreshGrants() }
        }
        Log.app.debug("onboarding: grant poll started")
    }

    /// Idempotent.
    private func stopPolling() {
        guard poll != nil else { return }
        poll?.invalidate()
        poll = nil
        Log.app.debug("onboarding: grant poll stopped")
    }

    private func advance() {
        if step < pages.count - 1 {
            step += 1
            render()
        } else {
            onFinish()
            close()
        }
    }

    // MARK: - Drawing

    /// A rounded capsule with an SF Symbol and a short label, in the app's colour.
    private static func pill(_ pill: Pill) -> NSView {
        let image = NSImageView(image: NSImage(systemSymbolName: pill.symbol,
                                              accessibilityDescription: nil) ?? NSImage())
        image.contentTintColor = brand
        image.symbolConfiguration = .init(pointSize: OnboardingMetrics.pillSymbol, weight: .semibold)
        let label = NSTextField(labelWithString: pill.text)
        label.font = .systemFont(ofSize: OnboardingMetrics.pillLabel, weight: .medium)
        label.textColor = brand
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [image, label])
        row.spacing = OnboardingMetrics.pillSpacing
        row.edgeInsets = OnboardingMetrics.pillInsets
        row.wantsLayer = true
        row.layer?.backgroundColor = brand.withAlphaComponent(OnboardingMetrics.pillTint).cgColor
        row.layer?.cornerRadius = OnboardingMetrics.pillRadius
        return row
    }

    /// The headline, with `word` in the app's colour where it occurs. `word` is localized separately, so a
    /// translation accents its own word and not a fragment of another.
    private static func accented(_ text: String, word: String?) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let string = NSMutableAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: OnboardingMetrics.heroTitle, weight: .bold),
                         .foregroundColor: NSColor.labelColor,
                         .paragraphStyle: paragraph])
        if let word, let range = text.range(of: word, options: .caseInsensitive) {
            string.addAttribute(.foregroundColor, value: brand, range: NSRange(range, in: text))
        }
        return string
    }
}

// MARK: - This app's pages

extension OnboardingWindowController {
    /// The four pages, in order: the pitch, the one permission, where the app lives, and "All set". A fresh
    /// controller is built every time the wizard is shown, so every row re-reads its state and the walk
    /// starts at page one.
    ///
    /// Both list pages carry one or two rows, so both take the short height.
    static func make(store: SettingsStore, onFinish: @escaping () -> Void,
                     grantIsInPlace: @escaping () -> Bool,
                     grantMayHaveChanged: @escaping () -> Void) -> OnboardingWindowController {
        let words = Loc.onboarding
        let pages: [OnboardingPage] = [
            .hero(title: words.pitchHeadline,
                  accent: words.pitchAccent,
                  body: words.pitchBody,
                  pills: [Pill(symbol: "square.grid.2x2", text: words.pitchIconViewPill),
                          Pill(symbol: "desktopcomputer", text: words.pitchDesktopPill),
                          Pill(symbol: "folder", text: words.pitchPanelsPill)],
                  button: words.continueButton),
            .list(header: words.permissionHeader,
                  intro: words.permissionIntro,
                  items: GrantCatalogue.permissions(grantIsInPlace: grantIsInPlace),
                  advanceWhen: everyRequiredGrant,
                  height: OnboardingMetrics.shortListHeight),
            .list(header: words.homeHeader,
                  intro: words.homeIntro,
                  items: GrantCatalogue.home(store: store),
                  advanceWhen: anyOneDone,
                  height: OnboardingMetrics.shortListHeight),
            .final(title: words.doneHeadline, body: words.doneBody, button: words.finishButton),
        ]
        return OnboardingWindowController(pages: pages, onFinish: onFinish,
                                          grantMayHaveChanged: grantMayHaveChanged)
    }
}

// MARK: - The pages

/// A capsule on the first page: an SF Symbol and two or three words, in the app's colour.
struct Pill {
    let symbol: String
    let text: String
}

/// One page of the wizard. Order is the order the user walks them.
enum OnboardingPage {
    /// The app icon, a headline with one word accented, a short description, optional capsules, one button.
    case hero(title: String, accent: String?, body: String, pills: [Pill], button: String)
    /// A page of rows. `advanceWhen` decides whether its button reads *Continue* or *Skip*. `height` is
    /// fitted to how many rows the page carries.
    case list(header: String, intro: String, items: [GrantItem], advanceWhen: ([GrantItem]) -> Bool,
              height: CGFloat = OnboardingMetrics.listHeight)
    /// The last page. Its button finishes and closes the window.
    case final(title: String, body: String, button: String)

    /// The window's height while this page is shown. The window resizes around its top-left corner.
    var height: CGFloat {
        switch self {
        case .hero: OnboardingMetrics.heroHeight
        case let .list(_, _, _, _, height): height
        case .final: OnboardingMetrics.finalHeight
        }
    }
}

/// Every required row is done. The permission page's rule.
func everyRequiredGrant(_ items: [GrantItem]) -> Bool {
    items.filter(\.required).allSatisfy { $0.granted() }
}

/// Any one row is done. An optional page's rule.
func anyOneDone(_ items: [GrantItem]) -> Bool {
    items.contains { $0.granted() }
}

// MARK: - The row

/// One row of a list page: what it is, why it is wanted, and a trailing control that follows its state.
/// **Built once and updated in place.** Rebuilding the page to show a state that moved empties the window
/// and draws it again, which reads as a blink and a reload on every press and every poll tick.
///
/// While a flow is running the row keeps the button that started it, disabled, with a spinner beside it, and
/// the poll leaves that loading state alone until the flow reports back. A flow that reports more than once
/// settles the row on the first only.
@MainActor
private final class GrantRow {
    let view: NSStackView

    /// What the trailing control is showing. Compared before redrawing, so a refresh that changes nothing
    /// touches no view at all.
    private enum Shown: Equatable { case nothing, granted, notGranted, busy(String) }

    private let item: GrantItem
    private let window: () -> NSWindow?
    private let focusReturn: FocusReturnWatch
    /// Called once a flow has reported back: the page's stepping button may have to change with it.
    private let didFinish: () -> Void
    private let trailing = NSView()
    private var shown: Shown = .nothing
    private var busy = false

    init(item: GrantItem, window: @escaping () -> NSWindow?, focusReturn: FocusReturnWatch,
         didFinish: @escaping () -> Void) {
        self.item = item
        self.window = window
        self.focusReturn = focusReturn
        self.didFinish = didFinish

        let title = NSTextField(labelWithString: item.title)
        title.font = .systemFont(ofSize: OnboardingMetrics.rowTitle, weight: .semibold)
        let titleRow = NSStackView(views: [title])
        titleRow.spacing = 6
        if item.required {
            let required = Loc.onboarding.requiredMark
            let warn = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                                  accessibilityDescription: required) ?? NSImage())
            warn.contentTintColor = .systemOrange
            warn.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
            warn.toolTip = required
            titleRow.addArrangedSubview(warn)
        }
        let why = NSTextField(wrappingLabelWithString: item.why)
        why.font = .systemFont(ofSize: OnboardingMetrics.rowWhy)
        why.textColor = .secondaryLabelColor
        why.preferredMaxLayoutWidth = OnboardingMetrics.rowTextWidth
        let text = NSStackView(views: [titleRow, why])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        text.widthAnchor
            .constraint(lessThanOrEqualToConstant: OnboardingMetrics.rowTextWidth).isActive = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view = NSStackView(views: [text, spacer, trailing])
        view.alignment = .centerY
        view.spacing = 12
        refresh()
    }

    /// Re-reads the state and redraws the trailing control only if it should look different. A row whose flow
    /// is still running keeps its loading state: the poll must not take it away.
    func refresh() {
        guard !busy else { return }
        show(item.granted() ? .granted : .notGranted)
    }

    private func show(_ next: Shown) {
        guard next != shown else { return }
        shown = next
        trailing.subviews.forEach { $0.removeFromSuperview() }
        let content: NSView
        switch next {
        case .nothing:
            content = NSView()
        case .busy(let title):
            let button = Self.button(title)
            button.isEnabled = false
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.isIndeterminate = true
            spinner.startAnimation(nil)
            let pair = NSStackView(views: [spinner, button])
            pair.spacing = 8
            content = pair
        case .granted:
            let done = NSTextField(labelWithString: item.doneTitle)
            done.font = .systemFont(ofSize: OnboardingMetrics.rowTrailing)
            done.textColor = .secondaryLabelColor
            if let remove = item.remove, let title = item.removeTitle {
                let button = Self.button(title)
                button.actionHandler = { [weak self] in
                    guard let self else { return }
                    self.start(title) { settle in remove(self.window(), settle) }
                }
                let pair = NSStackView(views: [done, button])
                pair.spacing = 8
                content = pair
            } else {
                content = done
            }
        case .notGranted:
            let button = Self.button(item.buttonTitle)
            button.actionHandler = { [weak self] in
                guard let self else { return }
                self.start(self.item.buttonTitle) { settle in self.item.action(self.window(), settle) }
            }
            content = button
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        trailing.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: trailing.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailing.trailingAnchor),
            content.topAnchor.constraint(equalTo: trailing.topAnchor),
            content.bottomAnchor.constraint(equalTo: trailing.bottomAnchor),
        ])
    }

    /// Runs one flow with the row in its loading state, reads the state again when it reports back, and
    /// settles who is in front. The order matters: the row is right before anything is activated.
    private func start(_ title: String, _ flow: (_ settle: @escaping () -> Void) -> Void) {
        busy = true
        show(.busy(title))
        var settled = false
        flow { [weak self] in
            guard !settled else { return }
            settled = true
            guard let self else { return }
            self.busy = false
            self.refresh()
            self.didFinish()
            self.item.reclaimFocusIfNeeded(self.window())
            if let opened = self.item.mayOpen { self.focusReturn.whenQuit(opened, bringBack: self.window()) }
        }
    }

    private static func button(_ title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        return button
    }
}

// MARK: - The numbers

/// Every size the wizard uses, in points, from the skill's `Metrics`. Fitted by eye in the running window,
/// round after round. Reproduce them; do not improve on them.
enum OnboardingMetrics {
    static let windowWidth: CGFloat = 540
    /// Page heights, by page. The window resizes around its top-left corner, so the title bar stays put.
    static let heroHeight: CGFloat = 440
    /// A list page of five rows.
    static let listHeight: CGFloat = 560
    /// A list page of one or two rows, which is every list page this app has.
    static let shortListHeight: CGFloat = 440
    static let finalHeight: CGFloat = 400

    static let heroIcon: CGFloat = 104
    static let heroTitle: CGFloat = 26
    static let heroBody: CGFloat = 14
    /// The widest a hero's text gets before it wraps, inside a 540 window.
    static let heroTextWidth: CGFloat = 440
    static let heroSpacing: CGFloat = 18
    static let heroTitleToBody: CGFloat = 10
    static let heroInsets = NSEdgeInsets(top: 32, left: 40, bottom: 36, right: 40)

    static let listTitle: CGFloat = 22
    static let listIntro: CGFloat = 13
    static let listIntroWidth: CGFloat = 460
    static let listSpacing: CGFloat = 14
    static let listIntroToList: CGFloat = 20
    static let listToFooter: CGFloat = 24
    static let listRowSpacing: CGFloat = 12
    static let listInsets = NSEdgeInsets(top: 28, left: 40, bottom: 28, right: 40)
    /// The list is the page's width less both insets.
    static let listSideInset: CGFloat = 80

    static let rowTitle: CGFloat = 14
    static let rowWhy: CGFloat = 12
    static let rowTrailing: CGFloat = 13
    /// The widest a row's title and explanation get, leaving room for the trailing control.
    static let rowTextWidth: CGFloat = 320

    static let pillSymbol: CGFloat = 11
    static let pillLabel: CGFloat = 11.5
    static let pillInsets = NSEdgeInsets(top: 5, left: 9, bottom: 5, right: 9)
    static let pillRadius: CGFloat = 13
    static let pillSpacing: CGFloat = 4
    static let pillTint: CGFloat = 0.10
    static let pillRowWidth: CGFloat = 460
}
