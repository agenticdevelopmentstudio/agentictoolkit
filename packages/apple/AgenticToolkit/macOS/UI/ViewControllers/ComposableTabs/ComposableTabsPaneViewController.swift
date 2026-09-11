import AppKit
import Combine

import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// One leaf of a tab: registry-vended content under a pane title bar, plus —
/// while arrange mode is on — the scrim and toolbar that change the layout
/// around it.
///
/// The chrome, the controls, the gear and the spacing all come from
/// `PaneViewController`; what is left here is the three things only a project
/// window knows — which registry vends the content, which background draws the
/// active-pane outline, and what arrange mode does over the top.
///
/// Nothing rearranges the layout while the user is working in it. Arrange mode
/// is a mode precisely so that the affordance can be big and central instead of
/// a small pull-down permanently in the corner of every pane.
@MainActor
public final class ComposableTabsPaneViewController: PaneViewController {

    public let nodeID: UUID
    public let paneNumber: Int
    public let viewID: ComposableTabsViewID
    /// See `ComposableTabsChild.thicknessFraction`.
    public var thicknessFraction: CGFloat?
    private weak var project: ProjectWorkspace?

    private var arrangeOverlay: ComposableTabsArrangeOverlayView?
    private var arrowKeyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    /// Set by the enclosing tree when a tab holds more than one pane of this
    /// kind. `nil` — the common case — leaves the identifier unnumbered.
    private var paneIndex: Int?

    public init(
        nodeID: UUID,
        paneNumber: Int,
        viewID: ComposableTabsViewID,
        project: ProjectWorkspace
    ) {
        self.nodeID = nodeID
        self.paneNumber = paneNumber
        self.viewID = viewID
        self.project = project
        // The parameters, not `self` — stored properties are set, but `self` is
        // not usable until `super.init` returns.
        super.init(stateStore: ProjectPaneStateStore(project: project, nodeID: nodeID))
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The backdrop that draws the active-pane outline. Unchanged — it is the
    /// reason this pane has a container of its own at all.
    public override func makeContainerView() -> NSView {
        ComposableTabsPaneBackgroundView(nodeID: nodeID)
    }

    /// `nil` only if the project went away first.
    public override func makeContentViewController() -> NSViewController? {
        guard let project else { return nil }
        return project.layout.registry.makeContentViewController(
            for: viewID,
            nodeID: nodeID,
            project: project,
            paneNumber: paneNumber
        )
    }

    /// The active-pane border is drawn on the backdrop's own layer, so the
    /// chrome is held off its edge by that much or the border lands under it.
    public override var contentInset: CGFloat { Self.borderInset }

    /// What this pane is called, as the registry names it. The same string the
    /// Add popup offers, so a pane and the choice that made it match — and only
    /// used when the content does not name itself.
    public override var fallbackTitle: String { paneName }

    /// `pane.<content-type>`, numbered only when the tab holds more than one of
    /// this kind. The number comes from the tree, which is the only thing that
    /// can know.
    public override var paneAccessibilityIdentifier: String {
        paneIndex.map { "\(paneTypeIdentifier).\($0)" } ?? paneTypeIdentifier
    }

    /// `pane.terminal` from `whippet.terminal` — the identifier is about the
    /// kind of pane, so the vendor prefix that keeps registry keys unique
    /// between apps is not part of it.
    public var paneTypeIdentifier: String {
        let kind = viewID.rawValue.split(separator: ".").last.map(String.init) ?? viewID.rawValue
        return "pane.\(AccessibilityID.slug(kind))"
    }

    /// Called by the root after any change to the tree. Re-stamping the view is
    /// safe at any time and is what makes a *move* renumber both panes.
    public func assignPaneIndex(_ index: Int?) {
        guard paneIndex != index else { return }
        paneIndex = index
        guard isViewLoaded else { return }
        view.accessibilityID(paneAccessibilityIdentifier)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.publisher(for: ComposableTabsArrangeMode.didChangeNotification)
            .sink { [weak self] notification in
                guard let self, let window = notification.object as? NSWindow,
                      window === self.view.window else { return }
                self.updateArrangeOverlay()
            }
            .store(in: &cancellables)

        // Any pane moving changes what every *other* pane may do — the last
        // pane in a column loses its `Up`, the last pane in the tab loses its
        // `Remove` — so availability is refreshed from the tree, not from the
        // pane that happened to act.
        NotificationCenter.default.publisher(for: ComposableTabsViewController.layoutDidChangeNotification)
            .sink { [weak self] _ in self?.arrangeOverlay?.refreshAvailability() }
            .store(in: &cancellables)

        // A closing window takes its panes with it without ever leaving arrange
        // mode, and `deinit` cannot touch the monitor — it is nonisolated.
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)
            .sink { [weak self] notification in
                guard let self, let window = notification.object as? NSWindow,
                      window === self.view.window else { return }
                self.removeArrangeOverlay()
            }
            .store(in: &cancellables)
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        // Also the re-entry point after a move: `rebuild(from:)` re-hosts this
        // controller, and the pane has to come back with the scrim it left with.
        updateArrangeOverlay()
    }

    /// The active-pane border is drawn on the backdrop's own layer, so the
    /// content is held off its edge by that much or the border lands under it.
    private static let borderInset: CGFloat = 2

    /// Called by the enclosing split when this pane leaves the tree for good.
    /// The pane's content may be holding shells or file-system watchers, and
    /// "released at some point after the last reference drops" is not good
    /// enough for a child process.
    public func paneWillBeRemoved() {
        removeArrangeOverlay()
        (contentViewController as? PaneContentTeardown)?.paneContentWillBeDiscarded()
    }

    // MARK: - Arrange mode

    /// The split holding this pane, as AppKit knows it. Deliberately not
    /// `host`: everything under this MARK is the arrange overlay, and the
    /// overlay is installed only on a pane whose view is in a window, so
    /// `parent` is set by definition and asking the screen is asking the right
    /// question. Named apart from `ComposableTabsViewController.enclosingSplit`,
    /// which answers the same question about a tree nobody has displayed —
    /// three rounds of this task were spent on readers picking the wrong one of
    /// several spellings of "the split holding this".
    private var enclosingSplitOnScreen: ComposableTabsViewController? {
        parent as? ComposableTabsViewController
    }

    /// What this pane is called, as the registry names it. The same string the
    /// Add popup offers, so a pane and the choice that made it match.
    var paneName: String {
        let registry = (project?.layout ?? ComposableTabsLayout.placeholderOnly()).registry
        return registry.descriptor(for: viewID).displayName
    }

    private func updateArrangeOverlay() {
        if ComposableTabsArrangeMode.shared.isEnabled(in: view.window) {
            installArrangeOverlay()
        } else {
            removeArrangeOverlay()
        }
    }

    private func installArrangeOverlay() {
        guard arrangeOverlay == nil else {
            arrangeOverlay?.refreshAvailability()
            return
        }

        let overlay = ComposableTabsArrangeOverlayView(frame: view.bounds)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.paneName = paneName
        overlay.canAdd = { [weak self] in self?.addChoices().isEmpty == false }
        overlay.canRemove = { [weak self] in
            guard let self else { return false }
            return self.enclosingSplitOnScreen?.canRemoveLeaf(self) ?? false
        }
        overlay.availableDirections = { [weak self] in
            guard let self else { return [] }
            return self.enclosingSplitOnScreen?.availableMoveDirections(for: self) ?? []
        }
        overlay.onAdd = { [weak self] in self?.presentAddSheet() }
        overlay.onRemove = { [weak self] in self?.confirmAndRemove() }
        overlay.onMove = { [weak self] direction in self?.move(direction) }
        overlay.onDone = { [weak self] in
            guard let window = self?.view.window else { return }
            ComposableTabsArrangeMode.shared.setEnabled(false, in: window)
        }

        // Above the content, inside the active-pane border.
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.borderInset),
            view.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: Self.borderInset),
            overlay.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.borderInset),
            view.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: Self.borderInset)
        ])
        arrangeOverlay = overlay
        overlay.refreshAvailability()

        installArrowKeyMonitor()
    }

    private func removeArrangeOverlay() {
        arrangeOverlay?.removeFromSuperview()
        arrangeOverlay = nil
        if let arrowKeyMonitor {
            NSEvent.removeMonitor(arrowKeyMonitor)
            self.arrowKeyMonitor = nil
        }
    }

    /// While arranging, an arrow key moves the selected pane — the fastest way
    /// to push a pane where you want it is to keep pressing the direction.
    ///
    /// A local monitor rather than `keyDown`: the pane's content owns the first
    /// responder (a terminal, an editor), and it would eat the arrow long
    /// before this controller saw it.
    private func installArrowKeyMonitor() {
        guard arrowKeyMonitor == nil else { return }
        arrowKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Only the Bool crosses back out: `assumeIsolated` hands its result
            // across an isolation boundary, and NSEvent is not `Sendable`.
            let consumed = MainActor.assumeIsolated { self.handleKeyDown(event) }
            return consumed ? nil : event
        }
    }

    /// Return, Enter and Escape all mean "done arranging" — the mode is what
    /// they dismiss, and which of the three a person reaches for is a habit,
    /// not a distinction worth honouring.
    private static let exitKeyCodes: Set<UInt16> = [36, 76, 53]

    /// Whether the key was ours to act on, and was.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let window = view.window,
              // Not the pane's own window means a sheet is up, and Escape
              // there cancels the sheet rather than the mode behind it.
              event.window === window,
              ComposableTabsArrangeMode.shared.isEnabled(in: window) else { return false }

        if Self.exitKeyCodes.contains(event.keyCode) {
            // Every pane in the window has a monitor, so this runs more than
            // once; turning the mode off twice is a no-op.
            ComposableTabsArrangeMode.shared.setEnabled(false, in: window)
            return true
        }

        // One monitor per pane, but only the pane the user selected moves.
        guard ComposableTabsActivePane.shared.activeNodeID(in: window) == nodeID,
              let direction = ComposableTabsViewController.Direction.allCases.first(
                where: { $0.arrowKeyCode == event.keyCode }) else { return false }
        move(direction)
        return true
    }

    private func move(_ direction: ComposableTabsViewController.Direction) {
        guard let split = enclosingSplitOnScreen, split.move(self, direction) else {
            RefusalFeedback.announce()
            return
        }
    }

    /// The distinct views the spec will let this pane sit beside, named for the
    /// popup. Distinct, because the same view offered on two axes is one thing
    /// to add — the axis is the sheet's *other* question.
    private func addChoices() -> [ComposableTabsAddPaneViewController.Choice] {
        guard let split = enclosingSplitOnScreen else { return [] }
        let registry = split.layout.registry
        var seen = Set<ComposableTabsViewID>()
        return split.allowedInsertions(beside: self).compactMap { insertion in
            // The placeholder is the fallback for content this build does not
            // have, not something anyone means to add. Offering it puts an
            // empty pane one click away in a menu of real ones.
            guard insertion.viewID != .placeholder else { return nil }
            guard seen.insert(insertion.viewID).inserted else { return nil }
            let descriptor = registry.descriptor(for: insertion.viewID)
            return ComposableTabsAddPaneViewController.Choice(
                viewID: insertion.viewID,
                displayName: descriptor.displayName,
                symbolName: descriptor.symbolName
            )
        }
    }

    private func presentAddSheet() {
        let choices = addChoices()
        guard !choices.isEmpty else {
            RefusalFeedback.announce()
            return
        }
        let picker = ComposableTabsAddPaneViewController(choices: choices) { [weak self] viewID, direction in
            guard let self else { return }
            self.enclosingSplitOnScreen?.split(self, adding: viewID, direction: direction)
        }
        // A popover over the button that opened it, not a sheet off the title
        // bar: the question is about *this* pane, and a sheet drops it at the
        // top of a window that may hold five others.
        guard let anchor = arrangeOverlay?.addButtonView else {
            presentAsSheet(picker)
            return
        }
        present(picker, asPopoverRelativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY, behavior: .transient)
    }

    /// Removing a pane can throw work away — a running shell, an unsaved edit —
    /// and the pane's content is the only thing that knows whether it would.
    private func confirmAndRemove() {
        guard let split = enclosingSplitOnScreen, split.canRemoveLeaf(self) else {
            RefusalFeedback.announce()
            return
        }
        guard let warning = (contentViewController as? PaneContentRemovalConfirmation)?
            .removalConfirmationMessage else {
            split.remove(self)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove this pane?"
        alert.informativeText = warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")

        guard let window = view.window else {
            if alert.runModal() == .alertFirstButtonReturn { split.remove(self) }
            return
        }
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn else { return }
                // Re-resolved: the sheet was up while the tree could change.
                self.enclosingSplitOnScreen?.remove(self)
            }
        }
    }

    /// Whether the window's first responder lives inside this pane, so a
    /// removal can re-home focus rather than leaving the window without one.
    var containsFirstResponder: Bool {
        // A pane that was never shown has no view, and asking for one here
        // would build the whole content graph — on the removal path, purely to
        // throw it away. It also cannot hold the first responder, so the
        // answer is already known (`assignPaneIndex(_:)` guards the same way).
        guard isViewLoaded else { return false }
        guard let responder = view.window?.firstResponder as? NSView else { return false }
        var current: NSView? = responder
        while let candidate = current {
            if candidate === view { return true }
            current = candidate.superview
        }
        return false
    }
}
