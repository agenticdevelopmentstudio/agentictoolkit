import AppKit
import Combine

import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// Which pane the user is working in, tracked per window: the one they last
/// clicked in, or — with `activePaneFollowsMouse` on — the one under the
/// pointer.
///
/// AppKit has no "the first responder changed" notification, and a pane's
/// content swallows its own mouse events long before the pane sees them, so the
/// click is caught once for the whole app rather than by every pane installing
/// a monitor of its own (`dry`). Per window, because two document windows each
/// have a pane the user is working in.
///
/// The pointer arrives through the same monitor as the click, and through the
/// same hit test: "which pane is this point in" is one question with one
/// answer, and a second implementation of it in a tracking area would be a
/// second thing to keep in step with the view tree.
@MainActor
public final class ComposableTabsActivePane {

    public static let shared = ComposableTabsActivePane()

    /// Posted with the affected `NSWindow` as the object.
    public static let didChangeNotification =
        Notification.Name("AgenticToolkit.ComposableTabsActivePane.didChange")

    private var activeByWindow: [ObjectIdentifier: UUID] = [:]
    private var monitor: Any?
    private var cancellables = Set<AnyCancellable>()

    /// The windows holding panes, so that switching the setting on reaches the
    /// windows that were already open rather than only the next one. Weak: this
    /// is a convenience list, never an owner, and a closed window has to be
    /// able to go away without being told twice.
    private let paneWindows = NSHashTable<NSWindow>.weakObjects()

    /// The pane backdrops currently on screen, so the active spot can be handed
    /// on when the pane holding it goes away. A tab switch replaces every pane
    /// in the window and closing a pane takes one out from under the user;
    /// either way the window would otherwise keep pointing at a node nobody can
    /// see. Weak for the same reason `paneWindows` is.
    private let paneViews = NSHashTable<ComposableTabsPaneBackgroundView>.weakObjects()

    private var followsMouseObserver: UserSettingObserver<Bool>?

    private init() {
        // Local, not global: this only cares about the pointer in this app's
        // own windows, and a local monitor sees the events before the responder
        // chain does without needing accessibility permission.
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .mouseMoved]
        ) { event in
            MainActor.assumeIsolated { ComposableTabsActivePane.shared.record(event) }
            return event
        }

        followsMouseObserver = UserSettingObserver(UserSettings.activePaneFollowsMouse) { [weak self] _ in
            guard let self else { return }
            for window in paneWindows.allObjects { acceptMouseMoved(in: window) }
        }

        // Windows outlive nothing here, but their entries would: without this
        // the map grows by one dead key per closed document window.
        //
        // `DispatchQueue.main`, never `RunLoop.main`: the latter enqueues in
        // `.default` mode only, so anything posted while AppKit is running a
        // mouse-down in `.eventTracking` waits until the drag ends. The main
        // dispatch queue is drained in every mode. `UserSetting` documents the
        // same failure.
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)
            .compactMap { $0.object as? NSWindow }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] window in
                self?.activeByWindow.removeValue(forKey: ObjectIdentifier(window))
            }
            .store(in: &cancellables)
    }

    public func activeNodeID(in window: NSWindow?) -> UUID? {
        guard let window else { return nil }
        return activeByWindow[ObjectIdentifier(window)]
    }

    /// Whether `view` sits inside the pane the user is working in.
    ///
    /// A view in no pane at all — the standalone terminal window, the quick
    /// note panel — counts as active: "not the active pane" has to mean
    /// *another* pane holds the user, not that there are no panes to hold them.
    /// Same for a window no pane has claimed yet, which is a state that lasts
    /// until the first backdrop reaches a window.
    ///
    /// Deliberately blind to whether the window is key. What it answers is
    /// which pane the user is working in, and that does not change because a
    /// settings window came forward — a pane content that dimmed itself every
    /// time the user opened Settings would be reporting the wrong thing at
    /// exactly the moment they were looking.
    public func isInActivePane(_ view: NSView) -> Bool {
        var candidate: NSView? = view
        while let current = candidate {
            if let background = current as? ComposableTabsPaneBackgroundView {
                guard let active = activeNodeID(in: view.window) else { return true }
                return active == background.nodeID
            }
            candidate = current.superview
        }
        return true
    }

    public func activate(nodeID: UUID, in window: NSWindow) {
        let key = ObjectIdentifier(window)
        guard activeByWindow[key] != nodeID else { return }
        activeByWindow[key] = nodeID
        NotificationCenter.default.post(name: Self.didChangeNotification, object: window)
    }

    /// Told by each pane's backdrop as it lands in a window.
    ///
    /// The window is kept so a later change to `activePaneFollowsMouse` can
    /// reach it, and a pane claims the active spot whenever no pane on screen
    /// holds it: a window nobody has clicked in yet still has a pane the user
    /// is typing into, and so does one whose active pane has just been replaced
    /// by a tab switch.
    public func paneDidAppear(_ pane: ComposableTabsPaneBackgroundView, in window: NSWindow) {
        paneWindows.add(window)
        paneViews.add(pane)
        acceptMouseMoved(in: window)
        if livePane(for: activeNodeID(in: window), in: window) == nil {
            activate(nodeID: pane.nodeID, in: window)
        }
    }

    /// Told by each pane's backdrop as it leaves a window — closed, or swapped
    /// out by a tab switch.
    ///
    /// A window whose entry outlives the pane it names is a window where
    /// `isInActivePane` answers "no" for every pane on screen: nothing is
    /// outlined, and `record` never hands the keyboard on, because the pointer
    /// only takes focus when it *changes* the active pane and the pane it moves
    /// into is never the phantom one. So the spot is handed to a surviving pane,
    /// and to no pane at all only when the window has none left — which is the
    /// state a fresh pane's arrival is already written to claim.
    public func paneDidDisappear(_ pane: ComposableTabsPaneBackgroundView, from window: NSWindow) {
        paneViews.remove(pane)
        let key = ObjectIdentifier(window)
        guard activeByWindow[key] == pane.nodeID else { return }
        if let successor = livePanes(in: window).first {
            activeByWindow[key] = successor.nodeID
        } else {
            activeByWindow.removeValue(forKey: key)
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: window)
    }

    /// The pane in `window` carrying `nodeID`, if one is on screen.
    private func livePane(for nodeID: UUID?, in window: NSWindow) -> ComposableTabsPaneBackgroundView? {
        guard let nodeID else { return nil }
        return livePanes(in: window).first { $0.nodeID == nodeID }
    }

    /// A hidden pane is on screen as far as this is concerned — a collapsed
    /// split is still the user's pane. Only a pane out of the window entirely
    /// has stopped being somewhere the keys can go.
    private func livePanes(in window: NSWindow) -> [ComposableTabsPaneBackgroundView] {
        paneViews.allObjects.filter { $0.window === window }
    }

    /// Switched on, and never back off. `acceptsMouseMovedEvents` is the
    /// window's, not this class's — anything else in the window may have asked
    /// for the same events — so turning the setting off stops this tracker
    /// acting on moves rather than stopping the window from hearing about them.
    /// What that costs is events this class ignores.
    private func acceptMouseMoved(in window: NSWindow) {
        guard UserSettings.activePaneFollowsMouse.currentValue else { return }
        window.acceptsMouseMovedEvents = true
    }

    private func record(_ event: NSEvent) {
        guard let window = event.window else { return }
        let following = event.type == .mouseMoved
        if following, !followsMouse(in: window) { return }

        guard let chain = paneChain(under: event, in: window),
              let background = chain.last as? ComposableTabsPaneBackgroundView else { return }

        // A click that has not moved the user is a click inside the pane they
        // are already in, and there is nothing to say about it. The pointer
        // merely passing through is the same thing said far more often — and
        // taking the keyboard again on every one of those moves would interrupt
        // whatever the user was doing with it inside the pane.
        guard activeNodeID(in: window) != background.nodeID else { return }

        // A click carries its own focus: the view under it takes first
        // responder the ordinary AppKit way. The pointer carries nothing, so a
        // pane it moves into would be outlined as active while the keys kept
        // going to the pane the user left.
        //
        // Focus is taken *before* the pane is activated, because the pane the
        // user left may refuse to give the keyboard up — a text field failing
        // validation in `resignFirstResponder` is AppKit's ordinary way of
        // saying "finish this first". Outlining the new pane anyway would point
        // at a pane the keys are not going to, so a refusal leaves both where
        // they were and the pointer changes nothing.
        if following, case .refused = takeFocus(within: chain, in: window) { return }
        activate(nodeID: background.nodeID, in: window)
    }

    /// Whether the pointer is entitled to move the active pane in this window.
    private func followsMouse(in window: NSWindow) -> Bool {
        guard UserSettings.activePaneFollowsMouse.currentValue else { return false }
        // The pointer resting over a window behind the front one says nothing
        // about where the user is typing — the key window still has the keys.
        // A sheet has them outright, and it is the sheet the user is answering.
        guard window.isKeyWindow, window.attachedSheet == nil else { return false }
        // Arrange mode is for moving panes about rather than working in them,
        // and its toolbar is what the keyboard belongs to while it is on.
        return !ComposableTabsArrangeMode.shared.isEnabled(in: window)
    }

    /// The views under the pointer, innermost first, out to the pane's backdrop
    /// — or `nil` when the point is not inside a pane at all.
    private func paneChain(under event: NSEvent, in window: NSWindow) -> [NSView]? {
        guard let contentView = window.contentView else { return nil }
        let point = contentView.convert(event.locationInWindow, from: nil)

        // The point landed on whatever the pane's content put there; the pane
        // it belongs to is the first backdrop out from it.
        var chain: [NSView] = []
        var view = contentView.hitTest(point)
        while let candidate = view {
            chain.append(candidate)
            if candidate is ComposableTabsPaneBackgroundView { return chain }
            view = candidate.superview
        }
        return nil
    }

    /// What came of trying to hand the keyboard to the pane under the pointer.
    private enum FocusOutcome {
        /// The keys are in the pane under the pointer — either just moved
        /// there, or already there.
        case taken
        /// Nothing in the pane wanted the keyboard. The pointer still owns the
        /// outline; the first responder stays where it was.
        case nowhereToPut
        /// The view holding the keyboard would not give it up.
        case refused
    }

    /// Hand the keyboard to whatever a click at this point would have handed it
    /// to: the innermost view under the pointer that will take it.
    ///
    /// Walking out from the pointer rather than asking the pane for one answer
    /// is what lets a pane with two things to type in — a file browser's list
    /// and the filter field above it — give the keys to the one the pointer is
    /// actually over. A pane with nothing to type in keeps the outline and
    /// leaves the first responder where it was, which is the honest outcome:
    /// there was nowhere in it for the keys to go.
    ///
    /// `acceptsFirstResponder` is a claim, not a promise — `makeFirstResponder`
    /// still returns false when the *outgoing* responder refuses to resign, and
    /// when the incoming one declines the appointment it was offered. The first
    /// is the whole window saying no and ends the walk; the second is only this
    /// view saying no, so the walk carries on outwards and the pane's next
    /// candidate gets its turn.
    @discardableResult
    private func takeFocus(within chain: [NSView], in window: NSWindow) -> FocusOutcome {
        let original = window.firstResponder
        for view in chain where view.acceptsFirstResponder {
            guard window.firstResponder !== view else { return .taken }
            if window.makeFirstResponder(view) { return .taken }
            // Which of the two refused is readable from where the keyboard
            // ended up. A view that declines the appointment leaves the window
            // itself holding it, having already let the old responder go — so
            // the next candidate outwards is worth offering. Anything else
            // means the old responder is still holding on, and it will refuse
            // every candidate the same way.
            guard window.firstResponder === window else { return .refused }
        }
        // Nowhere to put them — but the offers made on the way here were not
        // free. Every declined candidate cost the *outgoing* responder its
        // claim (that is exactly what the `=== window` check above reads), so
        // an exhausted walk can end with the keys on the window rather than
        // where they started: the user's text cursor gone from the field they
        // were typing in, taken by a pointer that merely crossed a pane with
        // nothing to type in. `.nowhereToPut` promises the caller the opposite
        // — "the first responder stays where it was" — so make that true
        // before saying it.
        guard window.firstResponder !== original else { return .nowhereToPut }
        // Restored: nothing moved after all, and the pointer may take the
        // outline. Not restored: the window holds the keys and no pane has
        // them, so the outline must not move either — the caller reads
        // `.refused` as "leave both where they were", which is the closest
        // this can get to honest.
        return window.makeFirstResponder(original) ? .nowhereToPut : .refused
    }
}

/// A pane's backdrop, which also draws the "this is the pane you are working
/// in" border. It is one view rather than an overlay so the border can never
/// end up under the pane's content.
///
/// Two planes, not one. The outer edge — the track the active-pane border is
/// drawn in — is the *workspace's* backdrop, the same plane as the frame
/// spacing, the gutters between panes and the tab attached to the workspace's
/// edge. The pane's own fill starts inside that track. Painted as one plane it
/// put a hairline of window background between the tab and the pane it belongs
/// to, all the way round the workspace, and the tab read as something stuck on
/// top of the workspace rather than part of it.
@MainActor
public final class ComposableTabsPaneBackgroundView: NSView, Themeable {

    /// How far the pane's own fill — and with it every piece of its chrome —
    /// is held off this view's edge, leaving the active-pane border somewhere
    /// to draw. Lives here because this is the view that draws that border.
    public static let borderInset: CGFloat = 2

    public let nodeID: UUID

    /// The pane itself: `windowBackground`, the plane a pane paints, inside
    /// the backdrop track.
    private let fill = ThemedBackgroundView(role: .windowBackground)

    private var observer: ThemePaletteObserver?
    private var cancellables = Set<AnyCancellable>()

    /// The window this backdrop was last in, so that leaving one can be
    /// reported. `viewDidMoveToWindow` is told where the view has arrived and
    /// never where it came from, and by the time it runs `window` is already
    /// the new answer.
    private weak var lastWindow: NSWindow?

    /// The palette for this view's own `ThemeScope`, which is what every repaint
    /// below reads. `ThemePaletteObserver.currentPalette` is the app-wide answer
    /// and would undo the scope on every repaint that is not a theme change —
    /// a project window running its own scope would snap back to the app's the
    /// first time the user moved between panes.
    private var scopedPalette: SemanticPalette { resolvedThemeScope.palette }

    public init(nodeID: UUID) {
        self.nodeID = nodeID
        super.init(frame: .zero)
        self.wantsLayer = true

        // First subview, so it stays underneath the chrome the pane controller
        // adds after this initialiser returns.
        fill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fill)
        let inset = Self.borderInset
        NSLayoutConstraint.activate([
            fill.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            fill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            trailingAnchor.constraint(equalTo: fill.trailingAnchor, constant: inset),
            bottomAnchor.constraint(equalTo: fill.bottomAnchor, constant: inset)
        ])

        observer = ThemePaletteObserver(host: self) { [weak self] palette in self?.applyTheme(palette) }

        NotificationCenter.default.publisher(for: ComposableTabsActivePane.didChangeNotification)
            .sink { [weak self] notification in
                guard let self, let window = notification.object as? NSWindow,
                      window === self.window else { return }
                self.applyTheme(self.scopedPalette)
            }
            .store(in: &cancellables)

        // Two windows both drawing "the pane you are working in" is a lie —
        // only one of them is. Unfiltered because a key change moves focus
        // *between* windows: the one losing it has to redraw too.
        Publishers.Merge(
            NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification),
            NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
        )
        .sink { [weak self] _ in
            guard let self else { return }
            self.applyTheme(self.scopedPalette)
        }
        .store(in: &cancellables)

        // `DispatchQueue.main`, never `RunLoop.main`: the latter enqueues in
        // `.default` mode only, so a change made while AppKit tracks a mouse in
        // `.eventTracking` — a checkbox being clicked — would not repaint until
        // the mouse came up. `UserSetting` documents the same failure.
        UserSettings.shared.changes
            .filter { $0 == UserSettings.highlightActivePane.name }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.applyTheme(self.scopedPalette)
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let tracker = ComposableTabsActivePane.shared
        if let previous = lastWindow, previous !== window {
            tracker.paneDidDisappear(self, from: previous)
        }
        lastWindow = window
        if let window {
            tracker.paneDidAppear(self, in: window)
        }
        applyTheme(scopedPalette)
    }

    /// A sheet takes key from the window it is attached to, and the pane
    /// underneath is still the one the user is working in — so the document
    /// window counts as focused while it holds one.
    private var isWindowFocused: Bool {
        guard let window else { return false }
        return window.isKeyWindow || window.attachedSheet?.isKeyWindow == true
    }

    public func applyTheme(_ palette: SemanticPalette) {
        // The backdrop, not the window background — the same argument
        // `PaneSplitView.drawDivider` makes for a gutter. Everything around a
        // pane is one plane: the frame spacing, the gutters, and the tab docked
        // to the workspace's edge. Paint this track in the pane's own fill and
        // the tab is cut off from the workspace by a dark hairline.
        layer?.backgroundColor = NSColor(palette.projectPaneBackdrop).cgColor

        // A theme may override both the switch and the color; neither is set
        // until the user edits the theme's Project topic, so by default the
        // Projects settings panel decides.
        let overrides = palette.theme.project
        let highlights = overrides?.highlightActivePane ?? UserSettings.highlightActivePane.value
        let isActive = highlights
            && isWindowFocused
            && ComposableTabsActivePane.shared.activeNodeID(in: window) == nodeID
        // **Every** pane is outlined, and only the colour says which one is
        // active. A pane is a window-shaped thing, and a window has edges
        // whether or not it is the front one; outlining only the active pane
        // left every other pane as an unbounded field of `windowBackground`,
        // so two panes side by side read as one pane with a seam down it —
        // which is exactly what a file tree beside an editor must not look
        // like. The width is constant so that clicking between panes recolours
        // a line instead of moving one.
        layer?.borderWidth = 2
        // The accent for the active pane — the one line in the window drawn in
        // it, and the answer to "which pane am I in". Every other pane takes
        // the hairline tone the rest of the frame is drawn in
        // (`projectPaneOutline`), so the accent still stands alone rather than
        // being one highlight among several.
        layer?.borderColor = NSColor(
            isActive ? palette.projectActivePaneOutline : palette.projectPaneOutline).cgColor
    }
}
