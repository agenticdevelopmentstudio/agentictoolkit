//
//  WindowFooterStatusBarPresenter.swift
//  AgenticToolkit
//

import AppKit
import AgenticDeveloperToolkitUI

/// The AppKit conformer for `vscode.window.createStatusBarItem`: it renders
/// every shown status bar item into the trailing slot of each open window's
/// `WindowFooterBar`.
///
/// Task 5.5c built `ExtensionStatusBarPresenting` and named this home
/// (`WindowFooterBar.trailingAccessories`) without building it, the same way
/// `ExtensionQuickPickPresenting` was left for `ExtensionPickerPresenter`.
/// This is that conformer, and it is written here rather than a task later
/// because `MainThreadWindow.init` takes `statusBarPresenter` with no
/// default: the `window` namespace cannot be constructed in production
/// without one.
///
/// ### It never assigns the whole accessory array
///
/// `WindowFooterBar.trailingAccessories`'s setter removes every view already
/// in the slot before adding the new ones
/// (`WindowFooterBar.swift:35-45`), so a presenter that assigned its own
/// items to that property would silently delete whatever else the window had
/// put there. Instead this owns exactly **one container view per footer**,
/// finds it by `identifier` on each pass, appends it once if it is not
/// already present, and rewrites only that container's arranged subviews.
/// Everything else in the slot is untouched, and the identifier lookup is
/// what makes the presenter stateless with respect to windows — a window
/// that closes takes its container with it, and no bookkeeping here has to
/// notice.
///
/// ### One slot, two alignments
///
/// `vscode.StatusBarAlignment` has a left and a right
/// (`MainThreadWindow.swift:452-454`); this footer has a leading *status
/// string* and a single trailing accessory slot, and no leading accessory
/// slot at all. Both alignments therefore render into the trailing slot,
/// with the left-aligned items placed before the right-aligned ones so the
/// relative order an extension asked for survives even though the absolute
/// position cannot. Widening `WindowFooterBar` with a leading accessory slot
/// is a change to a submodule this repo consumes, not something to fake
/// here.
///
/// ### What it does not render, and why
///
/// `color` and `backgroundColor` arrive as flat VS Code theme-colour *ids*
/// (`ExtensionStatusBarItemRequest`'s own doc says so, and says why): ids
/// like `statusBarItem.warningBackground`, which this repo has no mapping
/// for — `SemanticPalette` is keyed by `ThemeRole`, a different and much
/// smaller vocabulary. Rendering them would mean inventing a translation
/// table, and guessing at it would make the wrong colour look deliberate.
/// They are carried truthfully on the request, so a later presenter that
/// grows the table can honour them; this one does not, and does not pretend
/// to.
@MainActor
public final class WindowFooterStatusBarPresenter: ExtensionStatusBarPresenting {

    /// Marks this presenter's own container inside a footer's accessory
    /// slot. Looked up on every pass rather than cached, so a window that
    /// opened after the last item was shown still gets one.
    private static let containerIdentifier =
        NSUserInterfaceItemIdentifier("extensions.statusbar.container")

    /// Every footer to render into, read fresh at render time rather than
    /// captured once — for `NSAlertMessagePresenter.window`'s reason: the
    /// set of open windows changes underneath a presenter that outlives
    /// them, and the answer has to be whatever is open when an extension
    /// actually asks.
    ///
    /// Not defaulted, deliberately: reaching `ProjectWindowManager.shared`
    /// from in here would make every test of this type stand up the real
    /// window manager, which is the same reason the seam this class conforms
    /// to exists at all.
    private let footers: () -> [WindowFooterBar]

    /// Runs `StatusBarItem.command` (`vscode.d.ts:7627-7631`) when the user
    /// clicks an item that has one. A closure rather than a `CommandRegistry`
    /// reference for the same reason as `footers` above; production routes it
    /// to the registry the extension host registered its commands with.
    private let onCommand: (String) -> Void

    /// Every item currently up, keyed by `internalID` — the key
    /// `removeStatusBarItem(internalID:)` is called with. The adaptor owns
    /// visibility and disposal, so an entry here means "shown, not
    /// disposed", and nothing in this file decides that.
    private var items: [String: ExtensionStatusBarItemRequest] = [:]

    public init(
        footers: @escaping () -> [WindowFooterBar],
        onCommand: @escaping (String) -> Void
    ) {
        self.footers = footers
        self.onCommand = onCommand
    }

    /// Renders the items already up into whatever windows are open now.
    ///
    /// `render()` runs on a change to the *model* — an item put up, an item
    /// taken down — and the set of footers is read fresh each time, which
    /// covers every window open at that moment. What it does not cover is the
    /// other direction: a window opened after the last change has a footer
    /// this presenter has never rendered into, so it showed nothing, and went
    /// on showing nothing until some extension happened to change an item.
    /// Opening a second project window lost the status bar.
    ///
    /// **The owner drives this; the presenter does not listen for it.** In
    /// production that is `ProjectWindowManager.onOpenProjectsChanged` →
    /// `ExtensionsCoordinator.projectWindowsDidChange()` →
    /// `ExtensionHostInstaller.windowsDidChange()` → here, which fires exactly
    /// when the set of project windows moves and names no other kind of
    /// window.
    ///
    /// This used to observe `NSWindow.didBecomeKeyNotification` with
    /// `object: nil` instead, and that observer was wrong in both directions
    /// in this app. It fired too little: the app is an `LSUIElement` menubar
    /// host that opens project windows under quiet presentation, without
    /// activating, so a new window routinely never becomes key and the bug
    /// above survived the fix that was meant to close it. And it fired too
    /// much: `object: nil` is *every* window, so a settings panel or a
    /// notes window taking focus re-rendered every footer for nothing. The
    /// reason given for it — that this type deliberately knows nothing about
    /// `ProjectWindowManager` — is satisfied by this method being `public`
    /// and called from outside, which it already was; observing a
    /// notification bought no independence, only a worse signal.
    ///
    /// A no-op with nothing up: a new window has nothing to receive, and the
    /// removal that emptied `items` already re-rendered every footer that was
    /// open then.
    public func windowsDidChange() {
        guard !items.isEmpty else { return }
        render()
    }

    // MARK: - ExtensionStatusBarPresenting

    public func putOrUpdateStatusBarItem(_ request: ExtensionStatusBarItemRequest) {
        items[request.internalID] = request
        render()
    }

    public func removeStatusBarItem(internalID: String) {
        // The protocol says this is safe to call for an id never put up, so
        // a miss is a no-op rather than a re-render of an unchanged model.
        guard items.removeValue(forKey: internalID) != nil else { return }
        render()
    }

    // MARK: - Rendering

    /// Re-renders every open footer from `items`. Called once per committed
    /// change (task 5.5c's Ruling 7: no coalescing), so every write an
    /// extension makes to an item it already put up arrives here.
    ///
    /// **An item's view outlives the change.** A view is matched to a request
    /// by `internalID` and updated in place; only an item that genuinely
    /// arrived or left is built or torn down, and only an item whose rank
    /// moved is re-inserted. The earlier version emptied the container and
    /// rebuilt every view on every pass, which is wrong for the commonest
    /// thing a status bar item does — `item.text = "…"` on a timer, which VS
    /// Code extensions write per second — three ways that a rebuild of one
    /// small stack view does not cost enough to excuse:
    ///
    /// - The tooltip an item carries is a `toolTip` on a view AppKit is
    ///   tracking. Replace the view mid-hover and the tooltip that was about
    ///   to appear never does, and the one on screen does not update — it
    ///   belongs to a view that left the hierarchy.
    /// - `resetCursorRects` runs when a view enters a window. A pointer
    ///   already resting on a clickable item keeps the pointing-hand cursor
    ///   from the view that just left, over a view that has not been asked
    ///   for its rects yet.
    /// - `accessibilityID` is set per view, so a UI test or an accessibility
    ///   client that reads the footer while a per-second item is up races a
    ///   view being destroyed between the query and the read. `dev.py ax`
    ///   sees an element that answers nothing.
    ///
    /// Reuse is keyed on `internalID` for the reason `items` and the
    /// accessibility identifier already are: it is minted per item and
    /// therefore total, so it cannot match two views or the wrong one.
    private func render() {
        let ordered = orderedItems()
        for footer in footers() {
            let container = container(in: footer)
            var reusable: [String: StatusItemView] = [:]
            for case let view as StatusItemView in container.arrangedSubviews {
                reusable[view.internalID] = view
            }

            let wanted: [StatusItemView] = ordered.map { request in
                guard let view = reusable.removeValue(forKey: request.internalID) else {
                    return makeItemView(request)
                }
                view.update(with: request)
                return view
            }

            // Whatever is still in `reusable` is an item that came down.
            for view in reusable.values {
                container.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            for (index, view) in wanted.enumerated()
            where container.arrangedSubviews.firstIndex(of: view) != index {
                container.insertArrangedSubview(view, at: index)
            }
            container.isHidden = ordered.isEmpty
        }
    }

    /// This presenter's container inside `footer`'s accessory slot, appending
    /// a fresh one if the footer does not have it yet. Appending is the only
    /// write to `trailingAccessories` anywhere in this file — see the type's
    /// own doc for why assigning it outright would be a bug.
    private func container(in footer: WindowFooterBar) -> NSStackView {
        let existing = footer.trailingAccessories.first {
            $0.identifier == Self.containerIdentifier
        }
        if let container = existing as? NSStackView { return container }

        let container = NSStackView()
        container.identifier = Self.containerIdentifier
        container.orientation = .horizontal
        container.spacing = 8
        container.alignment = .centerY
        container.setContentHuggingPriority(.required, for: .horizontal)
        footer.trailingAccessories += [container]
        return container
    }

    /// Left-aligned items first, then right-aligned; within each group,
    /// higher priority first.
    ///
    /// **An absent priority sorts last within its group, and is never read as
    /// zero** — Ruling 8 of task 5.5c forbids that coercion, and the ordering
    /// is where it would otherwise creep back in: an item with
    /// `priority: -5` genuinely asked to be ranked, and coercing `nil` to `0`
    /// would rank it *behind* an item that asked for nothing. Ties, including
    /// two items that both asked for nothing, fall back to `internalID`,
    /// which is minted per item and therefore total — so the order is stable
    /// across re-renders instead of following a dictionary's iteration.
    private func orderedItems() -> [ExtensionStatusBarItemRequest] {
        items.values.sorted { lhs, rhs in
            if lhs.alignment != rhs.alignment { return lhs.alignment == .left }
            switch (lhs.priority, rhs.priority) {
            case let (left?, right?) where left != right: return left > right
            case (.some, .none): return true
            case (.none, .some): return false
            default: return lhs.internalID < rhs.internalID
            }
        }
    }

    /// Identified by `internalID`, not `id`, for the same reason `items` is
    /// keyed by it: `id` is whatever the extension passed to
    /// `createStatusBarItem` — or, when it passed nothing, the extension
    /// identifier — so two items from one extension that asked for the same
    /// id, or from two extensions that happened to choose the same string,
    /// collide. An accessibility identifier that names two views addresses
    /// neither, which makes the item untestable exactly when there is more
    /// than one of it. `internalID` is minted per item and therefore total,
    /// so it is what everything else in this file already identifies by.
    ///
    /// Returns the concrete type rather than `NSView` because `render()`
    /// matches a footer's existing views back to requests through it — an
    /// `NSView` return would push that back to a cast at every call site.
    private func makeItemView(_ request: ExtensionStatusBarItemRequest) -> StatusItemView {
        let view = StatusItemView(request: request, onCommand: onCommand)
        view.accessibilityID("extensions.statusbar.item.\(request.internalID)")
        return view
    }
}

// MARK: - One item's view

/// One status bar item: its text, its tooltip, and — when it has a
/// `command` — a click that runs it.
///
/// A container around a `ThemedLabel` rather than a button, because the
/// footer is 22pt tall and every button primitive in
/// `AgenticDeveloperToolkitUI` draws a bezel sized for a dialog. The click
/// lands here rather than on the label because a non-editable
/// `NSTextField` does nothing with `mouseDown` and passes it to its
/// superview, which is exactly this view.
@MainActor
private final class StatusItemView: NSView {

    /// The item this view is, for the whole time it is up. Immutable because
    /// it is the key `render()` matches views back to requests on: a view
    /// whose identity could change would be reused for a different item.
    let internalID: String

    private let label: ThemedLabel
    private let onCommand: (String) -> Void

    /// Whatever `accessibilityRole()` answered before this view overrode it.
    /// Read once, after `super.init`, so that an extension which takes its
    /// `role` back away restores AppKit's own answer rather than a guess at
    /// what that answer was. `nil` until then, and never written again.
    private var inheritedAccessibilityRole: NSAccessibility.Role?

    /// `var`, because an extension may add, change or take away `command` on
    /// an item it already put up — and the cursor depends on it.
    private var command: String?

    init(request: ExtensionStatusBarItemRequest, onCommand: @escaping (String) -> Void) {
        self.internalID = request.internalID
        self.onCommand = onCommand
        self.label = ThemedLabel(string: request.text, role: .secondaryText, textRole: .caption)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
        inheritedAccessibilityRole = accessibilityRole()
        apply(request)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Rewrites this view to `request`, which `render()` has already checked
    /// carries the same `internalID`.
    ///
    /// Asserted rather than trusted: reuse keyed on the wrong id would show
    /// one extension's text under another's accessibility identifier, which
    /// is a bug that reads on screen as the feature working.
    func update(with request: ExtensionStatusBarItemRequest) {
        assert(request.internalID == internalID, "reused a status item view for a different item")
        apply(request)
    }

    /// Everything about this view that comes from the request — read by both
    /// `init` and `update(with:)`, so a field added to
    /// `ExtensionStatusBarItemRequest` cannot be honoured on first render and
    /// forgotten on the next one.
    private func apply(_ request: ExtensionStatusBarItemRequest) {
        let hadCommand = command != nil
        command = request.command
        label.stringValue = request.text

        // `tooltip` is the item's own; `name` is what VS Code shows in its
        // "hide this item" menu, which this footer has no equivalent of, so
        // it is the fallback rather than a second surface.
        toolTip = request.tooltip ?? request.name

        setAccessibilityLabel(request.accessibilityLabel ?? request.text)
        // `accessibilityRole` arrives as VS Code's own string
        // (`AccessibilityInformation.role`, an ARIA role). Only the one that
        // has an unambiguous AppKit counterpart is honoured; anything else
        // keeps the default rather than being mapped onto a guess. Set both
        // ways round on an update: an extension that takes the role away
        // should get the default back, not keep a stale `.button`.
        setAccessibilityRole(request.accessibilityRole == "button" ? .button : inheritedAccessibilityRole)

        // A view that gained or lost its command has the wrong cursor until
        // its rects are rebuilt, and AppKit only asks unprompted when the
        // view enters a window.
        if hadCommand != (command != nil) {
            window?.invalidateCursorRects(for: self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let command else {
            super.mouseDown(with: event)
            return
        }
        onCommand(command)
    }

    override func resetCursorRects() {
        guard command != nil else { return }
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
