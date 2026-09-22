import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS

/// The Conversations window's contents: the session shelf on the left, the
/// merged feed on the right, and the toolbar that discloses the one over the
/// other.
///
/// The System Settings look — an inset rounded panel with the window's material
/// running behind it, full height under the traffic lights — is *not* what an
/// `NSSplitViewItem(sidebarWithViewController:)` draws here: that fills its rect
/// with square, edge-to-edge sidebar material, in this window and in the
/// Settings window alike. So the shape is drawn by hand in the shelf, out of
/// the system's own material, and this type uses a plain split item
/// (`native-controls` honoured as far as AppKit will take it).
///
/// This type owns the wiring between the two halves — the shelf's ticks become
/// the feed's filter, the feed's roster becomes the shelf's rows — and nothing
/// about either half's contents.
@MainActor
public final class ConversationsSplitViewController: NSSplitViewController {

    private enum ItemID {
        static let toggleShelf = NSToolbarItem.Identifier("conversations.toggle-shelf")
        static let selectionMode = NSToolbarItem.Identifier("conversations.selection-mode")
    }

    /// The picker's segments, in the order `ConversationsSelectionMode`'s own
    /// `allCases` puts them — one bubble for one conversation, two for several.
    private static let selectionModeSegments: [ToolbarSegment] = [
        ToolbarSegment(symbol: "bubble.left", toolTip: ConversationsSelectionMode.single.title),
        ToolbarSegment(
            symbol: "bubble.left.and.bubble.right",
            toolTip: ConversationsSelectionMode.multi.title)
    ]

    public let shelf: ConversationsShelfViewController
    public let feed: ConversationsViewController

    /// Held because `NSToolbar.delegate` is weak: a delegate with no other owner
    /// dies the instant `configureWindowChrome` returns, and the titlebar comes
    /// up empty with no error to explain it.
    private var toolbarDelegate: WindowToolbarBuilder.Delegate?

    /// Fired when the mode changes from anywhere — the control, a menu item, a
    /// key command — so a host can remember it.
    public var onSelectionModeChanged: ((ConversationsSelectionMode) -> Void)?

    /// Whether the window is reading one conversation or several.
    ///
    /// The window's own copy of the answer, and the one place the two halves are
    /// told about it: the shelf changes what a click means, the feed changes
    /// whether a bubble opens and whether the composer is live.
    public var selectionMode: ConversationsSelectionMode = .multi {
        didSet {
            guard selectionMode != oldValue else { return }
            // The shelf first: switching to single mode narrows the hidden set to
            // one session, and the feed's own answer — whether its composer has a
            // destination — is read off what is left showing.
            shelf.selectionMode = selectionMode
            feed.selectionMode = selectionMode
            // Single mode *is* the list: it shows one conversation at a time
            // and the only ways to change which are clicking a row and the
            // move-selection commands, both of which need the shelf out. A
            // narrowing that leaves the reader looking at one conversation with
            // no way to reach another is the mode doing half its job.
            if selectionMode == .single { setShelfVisible(true) }
            updateSelectionModeControl()
            onSelectionModeChanged?(selectionMode)
        }
    }

    /// Switches to the other mode. The View menu item and the key command both
    /// come through here; the picker sets the mode it was clicked on instead,
    /// since a segment names a mode rather than a change.
    @objc public func toggleSelectionMode() {
        selectionMode = selectionMode.toggled
    }

    /// The toolbar picker's action.
    @objc private func selectionModeChanged(_ sender: NSSegmentedControl) {
        let modes = ConversationsSelectionMode.allCases
        guard modes.indices.contains(sender.selectedSegment) else { return }
        selectionMode = modes[sender.selectedSegment]
    }

    /// Keeps the picker reading as the mode the window is actually in — it is
    /// not the only way to change it.
    private func updateSelectionModeControl() {
        guard let control = toolbarDelegate?.segmentedControl(for: ItemID.selectionMode),
              let index = ConversationsSelectionMode.allCases.firstIndex(of: selectionMode)
        else { return }
        control.selectedSegment = index
    }

    /// The ⌘↑/⌘↓ monitor, live only while this window is on screen.
    private var selectionKeyMonitor: Any?

    /// What Tab walks in this window: the shelf's filter box and the feed's
    /// composer, and nothing else. Built in `viewDidLoad`, once both panes have
    /// loaded their views, and rewired whenever the composer is turned on or off
    /// or the shelf is collapsed.
    private var keyViewLoop: KeyViewLoop?

    public init(feed: ConversationsViewController) {
        self.feed = feed
        self.shelf = ConversationsShelfViewController()
        super.init(nibName: nil, bundle: nil)

        // The shelf draws the ticks, the feed owns what they mean, and a host
        // may have restored the feed's hidden set before either existed — so
        // the shelf starts from the feed rather than from empty, or the boxes
        // and the timeline disagree about which sessions are showing.
        shelf.setHidden(feed.hiddenSessions)
        shelf.onHiddenChanged = { [weak self] hidden in
            self?.feed.setHiddenSessions(hidden)
        }
        feed.onRosterChanged = { [weak self] sessions in
            self?.shelf.sessions = sessions
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    public override func viewDidLoad() {
        super.viewDidLoad()

        // A plain item, not `sidebarWithViewController:`. A sidebar item fills
        // its whole rect with the system's sidebar material, edge to edge and
        // square-cornered, and that backdrop is drawn behind everything the
        // shelf adds — so an inset panel on top of it still has full-bleed
        // material showing in the margin. The shelf draws its own inset panel
        // instead (see `ConversationsShelfViewController`), which is the only
        // way to get the System Settings outline in a window this app paints.
        let shelfItem = NSSplitViewItem(viewController: shelf)
        shelfItem.minimumThickness = 180
        // No maximum. A ceiling on the shelf is the app deciding how much of
        // the window a reader is allowed to spend on the list, and it is wrong
        // both ways: a long `project » branch` with a summary under it wants
        // more than any number picked here, and a reader who drags the divider
        // past it is told "no" by a pane that then springs back. What actually
        // bounds it is the feed's own minimum, which is a fact about the
        // *other* pane still being usable.
        shelfItem.canCollapse = true
        // The whole of "do not resize the window". The default collapse
        // behaviour resizes the *split view* and holds the siblings at their
        // width, and the split view here is the window's content — so
        // disclosing the shelf pushed the window 260 points wider and hiding
        // it pulled the window back. This is the other way up: the window
        // stays where the reader put it and the feed gives up the width.
        shelfItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        // Collapsed to begin with: the window's job is the conversation, and a
        // reader who has never needed to hide a session should not have to
        // dismiss a list to get at it. Unless the host restored single mode
        // before the view loaded, in which case the list is how the mode is
        // steered and it opens with it — the same answer the `didSet` gives
        // when the mode changes while the window is up.
        shelfItem.isCollapsed = selectionMode != .single
        shelfItem.holdingPriority = .defaultLow + 1

        let feedItem = NSSplitViewItem(viewController: feed)
        // Low enough that the shelf and the feed together always fit inside
        // this window's own minimum width (380). A pair of minimums that add
        // up to more than the window is a window AppKit has to widen the
        // moment the second pane appears, whatever the collapse behaviour
        // says.
        feedItem.minimumThickness = 180

        addSplitViewItem(shelfItem)
        addSplitViewItem(feedItem)

        // A plain `NSSplitView`, not the themed one and not a subclass of our
        // own: overriding `dividerColor` makes AppKit fall back to view-backed
        // dividers, and it then asks `shouldHideDivider(at:)` from inside
        // `_setupSplitView` while `splitViewItems` is still empty — an
        // NSRangeException that trapped the app on launch, three times, before
        // the subclass came back out. The shelf's panel is inset from its
        // trailing edge anyway, so there is no divider to hide.
        splitView.autosaveName = NSSplitView.AutosaveName("conversations-split")

        // Both panes have loaded their views by now — `addSplitViewItem` does
        // it — so the two fields exist to be threaded together.
        let loop = KeyViewLoop([shelf.filterTextField, feed.composerField].compactMap { $0 })
        keyViewLoop = loop
        feed.onComposerEnablementChanged = { [weak self] in self?.refreshKeyViewLoop() }
        refreshKeyViewLoop()
    }

    /// Rebuild the Tab order from what can be typed into right now.
    ///
    /// Called on every change that adds or removes a participant: the composer
    /// switching between single and multi mode, and the shelf collapsing — a
    /// collapsed pane's views are hidden, and Tab into a hidden filter box is
    /// focus the reader cannot see.
    private func refreshKeyViewLoop() {
        keyViewLoop?.refresh()
        // Set every time rather than once: the window's initial responder is
        // read when the window is first shown, and what is focusable then
        // depends on whether the shelf was restored collapsed.
        if let first = keyViewLoop?.first { view.window?.initialFirstResponder = first }
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        // The toolbar builds its items lazily, so the button usually does not
        // exist yet when `configureWindowChrome` runs. By the time the window is
        // on screen it does.
        updateToggleAppearance()
        updateSelectionModeControl()
        installSelectionKeyMonitor()
        refreshKeyViewLoop()
    }

    public override func viewWillDisappear() {
        super.viewWillDisappear()
        if let selectionKeyMonitor {
            NSEvent.removeMonitor(selectionKeyMonitor)
            self.selectionKeyMonitor = nil
        }
    }

    /// Takes this window's key commands and performs them.
    ///
    /// A local event monitor rather than a `performKeyEquivalent` override,
    /// because the shelf is usually **collapsed**: AppKit hides a collapsed
    /// split item's view, and it does not offer key equivalents to hidden views
    /// — so the one place the handler could naturally live is the one place it
    /// would not fire. The monitor also means there is a single implementation
    /// rather than one per pane, which matters because the keystroke is supposed
    /// to work wherever in the window the reader happens to be looking.
    ///
    /// The chords come from ``KeyCommandRegistry`` rather than being written
    /// here, which is what makes them rebindable in Settings — a monitor that
    /// compared key codes would keep answering to ⌘↑ whatever the user chose.
    ///
    /// Only this window's own commands are matched: another window's app-scope
    /// command is not this monitor's to fire, even though the registry can see
    /// it. And a selection move swallows the event only when the shelf actually
    /// moved, so ⌘↑ in multi mode, or at the top of the list, still means
    /// whatever it meant before.
    private func installSelectionKeyMonitor() {
        guard selectionKeyMonitor == nil else { return }
        selectionKeyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let self,
                  event.window === self.view.window,
                  let command = KeyCommandRegistry.shared.command(matching: event, scope: .app)
            else { return event }
            switch command.id {
            case ConversationsKeyCommands.moveSelectionUpID:
                return self.moveSelection(by: -1) ? nil : event
            case ConversationsKeyCommands.moveSelectionDownID:
                return self.moveSelection(by: 1) ? nil : event
            case ConversationsKeyCommands.toggleShelfID:
                self.toggleShelf()
                return nil
            default:
                return event
            }
        }
    }

    /// Move the shelf's pick by `delta`, reporting whether it moved.
    ///
    /// The single-mode guard lives here rather than in the monitor because it is
    /// part of what the command *means*: in multi mode there is no single pick
    /// to walk, so the command does nothing and the keystroke belongs to
    /// whatever else wanted it.
    @discardableResult
    public func moveSelection(by delta: Int) -> Bool {
        guard selectionMode == .single else { return false }
        return shelf.moveSelection(by: delta)
    }

    /// Whether the shelf is showing.
    public var isShelfVisible: Bool {
        guard let item = splitViewItems.first else { return false }
        return !item.isCollapsed
    }

    /// Shows the shelf if it is hidden, hides it if it is showing.
    @objc public func toggleShelf() { setShelfVisible(!isShelfVisible) }

    /// Slides the shelf out or away, doing nothing if it is already there.
    ///
    /// Separate from ``toggleShelf()`` because the mode switch is not a toggle:
    /// entering single mode must *show* the list, whether or not it was showing
    /// already, and a toggle asked to do that hides it half the time.
    public func setShelfVisible(_ visible: Bool) {
        guard let item = splitViewItems.first, item.isCollapsed == visible else { return }
        // Nothing on screen, nothing to slide: a mode restored before the
        // window is up has to leave the shelf in its *final* state, because
        // there is no animation to land and no completion to repaint from.
        guard view.window != nil else {
            item.isCollapsed = !visible
            updateToggleAppearance()
            refreshKeyViewLoop()
            return
        }
        // Inside an explicit animation group, with implicit animation allowed:
        // `item.animator()` on its own animates the divider while everything
        // laid out against it jumps to its final place on the first frame, so
        // the shelf's panel snapped to width while the pane was still sliding.
        // The group is also what gives the two halves one duration and one
        // curve instead of each finding its own.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            item.animator().isCollapsed = !visible
        } completionHandler: { [weak self] in
            // The toggle reads as the state it *reached*, so it is repainted
            // when the animation lands rather than when it starts. The Tab
            // order settles then too: a collapsing pane's views are hidden at
            // the end of the animation, not at the start.
            //
            // `assumeIsolated` rather than a `Task`: AppKit runs this handler
            // on the main thread, it is only the `@Sendable` signature that
            // loses that, and hopping would repaint a frame after the
            // animation instead of on it.
            MainActor.assumeIsolated {
                self?.updateToggleAppearance()
                self?.refreshKeyViewLoop()
            }
        }
        updateToggleAppearance()
    }

    // MARK: - Window chrome

    /// Installs the toolbar and the clear titlebar on the window hosting this
    /// controller. Called from the window controller's `configureWindow`,
    /// because a view controller does not own a window and should not go
    /// looking for one.
    public func configureWindowChrome(_ window: NSWindow) {
        let delegate = WindowToolbarBuilder.Delegate(
            items: [
                .button(
                    identifier: ItemID.toggleShelf,
                    symbol: "sidebar.left",
                    label: "Sessions",
                    action: #selector(toggleShelf)),
                .segmented(
                    identifier: ItemID.selectionMode,
                    label: "Conversations",
                    segments: Self.selectionModeSegments,
                    action: #selector(selectionModeChanged(_:))),
                .flexibleSpace
            ],
            target: self)
        toolbarDelegate = delegate

        let toolbar = delegate.makeToolbar(identifier: "conversations.toolbar")
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        // The three lines that make the titlebar clear: the content runs the
        // full height of the window, the titlebar draws no material of its own,
        // and no hairline is stamped across the join. Without the third, the
        // sidebar's inset panel is cut off by a line at the top.
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden

        updateToggleAppearance()
        updateSelectionModeControl()
    }

    /// Keeps the toggle reading as the state it toggles — filled and accented
    /// while the shelf is out, outlined and quiet while it is away.
    private func updateToggleAppearance() {
        guard let button = toolbarDelegate?.button(for: ItemID.toggleShelf) else { return }
        WindowToolbarBuilder.applyDisclosureAppearance(
            to: button,
            disclosed: isShelfVisible,
            outlineSymbol: "sidebar.left",
            filledSymbol: "sidebar.left",
            showTooltip: "Show Sessions",
            hideTooltip: "Hide Sessions")
    }
}
