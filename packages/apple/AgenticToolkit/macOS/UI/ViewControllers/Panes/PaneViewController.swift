import AgenticDeveloperToolkitUI
import AppKit

/// A pane: a title bar, some content, and enough memory to come back the way it
/// was left.
///
/// It knows nothing about split views, layout trees, tabs, projects or SQLite.
/// Three seams are the whole of it — a `PaneHost` it sends requests to, a
/// `PaneStateStore` it remembers itself through, and content it *probes* for
/// six optional capabilities. Every one of those is supplied from outside
/// (`dependency-injection`), which is what makes "deploy the same pane in a
/// different kind of view" a matter of supplying a different host rather than a
/// matter of editing this class.
///
/// Subclass hooks, all `open`: `makeContentViewController()`,
/// `makeContainerView()`, `makeOptionRows()`, `makeMenuItems()`,
/// `fallbackTitle`, `contentInset` and `paneAccessibilityIdentifier`. A
/// subclass that overrides none of them still gets a working, empty pane.
///
/// Content that implements none of the six capability protocols is a supported
/// case, not a degraded one: it gets `fallbackTitle`, no accessories, no
/// pane-specific options, the generic minimized glyph, a search field that
/// stays disabled and a display path that stops at the pane.
@MainActor
open class PaneViewController: NSViewController {

    /// Weak: the host owns the pane, always.
    public weak var host: PaneHost? {
        didSet { refreshControlAvailability() }
    }

    public let stateStore: PaneStateStore

    public let titleBar = PaneTitleBarView()

    /// The content this pane wraps, held as a child so AppKit keeps it alive,
    /// routes appearance callbacks to it, and puts it in the responder chain.
    public private(set) var contentViewController: NSViewController?

    /// Which edge this pane is currently docked to, or `nil` when it is whole.
    public private(set) var minimizedEdge: PaneEdge?

    public private(set) var isZoomed = false

    /// Fires when the content's selection changed. The window listens, so the
    /// footer's display path is recomputed by whoever knows the rest of the path.
    public var onSelectionChange: (() -> Void)?

    /// Fires when `resolvedTitle` changed. The pane's own title bar is not the
    /// only thing that shows it — the window's footer names the pane too — so
    /// the change is published rather than only painted here.
    public var onTitleChange: (() -> Void)?

    /// Internal rather than private so a test can check which edges the picker
    /// was opened with, without opening a popover.
    private(set) var minimizePicker: PaneMinimizePicker?

    private let contentContainer = NSView()
    private var minimizedStrip: PaneMinimizedStripView?

    /// Which edge the live strip was built for. The dock constraint and the
    /// strip's own hairline side are both decided at construction, so a strip
    /// built for one horizontal edge is wrong for the other and has to be
    /// replaced rather than re-shown.
    private var builtStripEdge: PaneEdge?

    /// Held so the rail can switch it off. A pane minimized to a side is pinned
    /// narrower than the title bar's own controls can fit, and a hidden view
    /// still takes part in Auto Layout — so leaving both sides pinned makes the
    /// item's 32pt maximum unsatisfiable, and AppKit recovers by breaking a
    /// constraint inside the title bar it happens to pick.
    private var titleBarTrailing: NSLayoutConstraint?
    /// The gear itself, drawn by the chrome that draws every other gear. What
    /// it *raises* is this pane's business — a menu — but what it looks like is
    /// the window chrome's single answer, and asking for it rather than
    /// respelling it keeps it that way (`dry`).
    private let gearButton = WindowOptionsDialog.makeGearButton(tooltip: "Pane options")

    /// The options dialog, while it is on screen.
    ///
    /// Weak, and internal rather than private: the presenter owns a sheet for
    /// exactly as long as it is up, and a pane still holding a dismissed one
    /// would answer `refreshTitle()` by renaming a heading nobody can see.
    private(set) weak var optionsSheet: OptionsDialogViewController?

    /// This pane's spacing, and where it comes from. `lazy` because it asks
    /// `inheritedPaneSpacing`, which a subclass overrides — so it cannot be
    /// built until `self` exists.
    public private(set) lazy var spacingOverride = PaneSpacingOverride(
        store: stateStore,
        inherited: { [weak self] in self?.inheritedPaneSpacing ?? Spacing() }
    )

    /// What the pane is *itself* holding the content off its edges by. Zero
    /// when the content applies the gap instead — which is the invariant this
    /// property exists to make testable.
    public private(set) var contentSpacingInsets = NSEdgeInsets()

    private var contentEdgeConstraints: (top: NSLayoutConstraint,
                                         leading: NSLayoutConstraint,
                                         bottom: NSLayoutConstraint,
                                         trailing: NSLayoutConstraint)?

    private var spacingControl: SpacingControl?
    private var spacingResetButton: NSButton?

    public init(stateStore: PaneStateStore = EphemeralPaneStateStore()) {
        self.stateStore = stateStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Subclass hooks

    /// The content. Called once, during `loadView()`.
    open func makeContentViewController() -> NSViewController? { nil }

    /// The pane's own background. A subclass with a selection border or a
    /// backdrop overrides this.
    open func makeContainerView() -> NSView { ThemedBackgroundView(role: .windowBackground) }

    /// What the title bar says when the content does not name itself.
    open var fallbackTitle: String { "Pane" }

    /// How far the content is held off the container's edges. A subclass that
    /// draws a border on the container needs room for it.
    open var contentInset: CGFloat { 0 }

    /// The identifier on the pane's container view. Subclasses that know what
    /// kind of content they hold make it specific, so a UI test can address one
    /// pane among several.
    open var paneAccessibilityIdentifier: String { "pane" }

    /// The spacing this pane falls back to when it has no override of its own.
    ///
    /// Content that already applies a gap names the global it is applying, so
    /// the per-pane control overrides *that* number rather than introducing a
    /// second one. Everything else inherits nothing, and a subclass that knows
    /// better overrides this.
    open var inheritedPaneSpacing: Spacing {
        (contentViewController as? PaneContentSpacingConsuming)?.inheritedPaneSpacing ?? Spacing()
    }

    /// The rows in the options dialog: the frame spacing control first, then
    /// the content's own rows.
    open func makeOptionRows() -> [NSView] {
        makeSpacingRows()
            + ((contentViewController as? PaneOptionsProviding)?.makePaneOptionRows() ?? [])
    }

    /// The pane's own items in the gear menu, above `Settings…`.
    ///
    /// Empty here, and deliberately so: a bare pane has nothing to offer but
    /// its settings, and it must not learn about split views to say so. A pane
    /// that lives in a layout knows which ways it can move, and that knowledge
    /// belongs to *that* pane (`srp`).
    open func makeMenuItems() -> [NSMenuItem] { [] }

    // MARK: - Loading

    open override func loadView() {
        let container = makeContainerView()
        container.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        container.accessibilityID(paneAccessibilityIdentifier)

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        titleBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleBar)
        container.addSubview(contentContainer)

        let titleBarTrailing = container.trailingAnchor.constraint(
            equalTo: titleBar.trailingAnchor, constant: contentInset)
        self.titleBarTrailing = titleBarTrailing

        NSLayoutConstraint.activate([
            titleBar.topAnchor.constraint(equalTo: container.topAnchor, constant: contentInset),
            titleBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: contentInset),
            titleBarTrailing,

            contentContainer.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: contentInset),
            container.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: contentInset),
            container.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: contentInset)
        ])

        if let content = makeContentViewController() {
            addChild(content)
            contentViewController = content
            let view = content.view
            view.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(view)
            let top = view.topAnchor.constraint(equalTo: contentContainer.topAnchor)
            let leading = view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor)
            let bottom = contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            let trailing = contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            NSLayoutConstraint.activate([top, leading, bottom, trailing])
            contentEdgeConstraints = (top, leading, bottom, trailing)
        }

        self.view = container
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        wireControls()
        wireContentCallbacks()
        spacingOverride.onChange = { [weak self] _ in self?.applyResolvedSpacing() }
        applyResolvedSpacing()
        installGear()
        refreshTitle()
        refreshAccessories()
        refreshControlAvailability()
        restorePersistedState()
    }

    // MARK: - Wiring

    private func wireControls() {
        titleBar.controls.onClose = { [weak self] in
            guard let self else { return }
            host?.paneDidRequestClose(self)
        }
        titleBar.controls.onZoom = { [weak self] in
            guard let self else { return }
            host?.paneDidRequestZoom(self)
        }
        titleBar.controls.onRestore = { [weak self] in
            guard let self else { return }
            host?.paneDidRequestRestore(self)
        }
        titleBar.controls.onMinimize = { [weak self] anchor in
            self?.presentMinimizePicker(from: anchor)
        }
    }

    /// The two capabilities that push rather than being pulled. Both are
    /// installed once, here, so the content never has to know who is listening.
    private func wireContentCallbacks() {
        (contentViewController as? PaneTitleProviding)?.onPaneTitleChange = { [weak self] in
            self?.refreshTitle()
        }
        (contentViewController as? PaneSelectionDescribing)?.onPaneSelectionChange = { [weak self] in
            self?.onSelectionChange?()
        }
    }

    private func installGear() {
        gearButton.target = self
        gearButton.action = #selector(showOptionsMenu)
        gearButton.accessibilityID("pane.options")
        gearButton.setAccessibilityLabel("Pane Options")
        titleBar.gearView = gearButton
    }

    /// What the gear raises: the pane's own items, then `Settings…`.
    ///
    /// Built fresh on every click, because what a pane may legally do — which
    /// ways it can move, above all — changes with the layout around it, and a
    /// menu built once at `viewDidLoad` would be answering for a layout that no
    /// longer exists.
    ///
    /// `autoenablesItems` is off deliberately. A menu raised from a button has
    /// no validation chain, so AppKit would grey out every item whose action
    /// nothing claims to validate; each item states its own availability
    /// instead (`explicit-over-implicit`).
    ///
    /// Internal rather than private so a test can read the menu without
    /// raising it — clicking a gear is not something a unit test can do.
    func makeOptionsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let items = makeMenuItems()
        for item in items { menu.addItem(item) }
        if !items.isEmpty { menu.addItem(.separator()) }

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(showOptionsDialog),
            keyEquivalent: ""
        )
        settings.target = self
        settings.image = NSImage(
            systemSymbolName: "slider.horizontal.3",
            accessibilityDescription: "Settings")
        settings.accessibilityID("pane.options.settings")
        menu.addItem(settings)

        return menu
    }

    @objc private func showOptionsMenu(_ sender: NSButton) {
        // `(0, 0)` is the button's own bottom-left — its content is unflipped —
        // and `popUp` lands the menu's top-left there, so the menu hangs below
        // the gear instead of covering it.
        makeOptionsMenu().popUp(positioning: nil, at: .zero, in: sender)
    }

    @objc private func showOptionsDialog() {
        let sheet = OptionsDialogViewController(
            heading: resolvedTitle,
            rows: makeOptionRows(),
            // Wide enough for the spacing control's diagram, which is the
            // widest thing any pane puts in here.
            width: 340,
            accessibilityPrefix: "pane.options"
        )
        sheet.onDone = { [weak sheet, weak self] in
            guard let sheet else { return }
            self?.dismiss(sheet)
        }
        sheet.onDidClose = { [weak self] in self?.optionsDialogDidClose() }
        optionsSheet = sheet
        presentAsSheet(sheet)
    }

    /// The spacing steppers coalesce their writes, so the last tick of a
    /// gesture is still waiting when the dialog goes away. The dialog closing
    /// *is* the end of the gesture — and closing the window closes it too — so
    /// this is where the pane stops waiting and writes.
    ///
    /// Internal rather than private so a test can end the gesture without
    /// putting a dialog on screen; nothing outside the framework has any
    /// business reaching it.
    func optionsDialogDidClose() {
        spacingOverride.flushPendingPersist()
    }

    private func presentMinimizePicker(from anchor: NSButton) {
        let edges = host?.availableMinimizeEdges(for: self) ?? []
        let picker = PaneMinimizePicker(availableEdges: edges) { [weak self] edge in
            guard let self else { return }
            host?.paneDidRequestMinimize(self, to: edge)
        }
        minimizePicker = picker
        picker.show(relativeTo: anchor)
    }

    // MARK: - Spacing

    /// Hands the gap to whichever of the two is applying it, and takes it back
    /// off the other. Safe to call repeatedly — it assigns, it does not
    /// accumulate (`idempotency`).
    public func applyResolvedSpacing() {
        let spacing = resolvedSpacing
        spacingControl?.value = spacing
        spacingResetButton?.isEnabled = spacingOverride.isOverridden

        if let consumer = contentViewController as? PaneContentSpacingConsuming {
            consumer.applyPaneSpacing(spacing)
            contentSpacingInsets = NSEdgeInsets()
        } else {
            contentSpacingInsets = spacingOverride.insets
        }

        contentEdgeConstraints?.top.constant = contentSpacingInsets.top
        contentEdgeConstraints?.leading.constant = contentSpacingInsets.left
        contentEdgeConstraints?.bottom.constant = contentSpacingInsets.bottom
        contentEdgeConstraints?.trailing.constant = contentSpacingInsets.right
    }

    /// Split out so `applyResolvedSpacing` reads as one idea; a subclass never
    /// needs it, since `inheritedPaneSpacing` is the hook.
    private var resolvedSpacing: Spacing { spacingOverride.resolved }

    /// The dialog's first rows: the picture, and the way back to inheriting.
    ///
    /// The control's own reset sets every number to zero, which is a *look* a
    /// user may want — so returning to the app's spacing needs its own button,
    /// and it is disabled while there is nothing to return from.
    public func makeSpacingRows() -> [NSView] {
        let control = SpacingControl(style: .frame, range: PaneSpacingOverride.range)
        control.value = spacingOverride.resolved
        control.onChange = { [weak self] value in self?.spacingOverride.setOverride(value) }
        control.accessibilityID("pane.options.spacing")
        spacingControl = control

        let reset = NSButton(title: "Use Default", target: nil, action: nil)
        reset.bezelStyle = .rounded
        reset.isEnabled = spacingOverride.isOverridden
        reset.accessibilityID("pane.options.spacing.reset")
        reset.setAccessibilityLabel("Use Default Spacing")
        // Target/action rather than a closure: the pane is the target, and it
        // outlives every dialog the button is ever put in, so the unowned
        // `target` reference cannot dangle and there is no retain cycle to
        // break — the pane raises the dialog, not the other way round.
        reset.target = self
        reset.action = #selector(resetSpacing)
        spacingResetButton = reset

        return [control, reset]
    }

    @objc private func resetSpacing() {
        spacingOverride.reset()
    }

    // MARK: - Reading the content

    public var resolvedTitle: String {
        (contentViewController as? PaneTitleProviding)?.paneTitle ?? fallbackTitle
    }

    /// What the content has selected, or `nil` — in which case a display path
    /// stops at this pane rather than showing an empty trailing segment.
    public var selectionDescription: String? {
        (contentViewController as? PaneSelectionDescribing)?.paneSelectionDescription
    }

    public var isSearchable: Bool { contentViewController is PaneSearchable }

    public var searchPlaceholder: String? {
        (contentViewController as? PaneSearchable)?.paneSearchPlaceholder
    }

    public func search(for query: String) {
        (contentViewController as? PaneSearchable)?.paneSearch(for: query)
    }

    /// The pane's name has three readers: its own title bar, the options
    /// dialog's heading, and — through `onTitleChange` — the window footer.
    /// Content that renames itself calls this, so all three are re-read
    /// together rather than leaving the dialog showing whatever the pane was
    /// called when it opened.
    public func refreshTitle() {
        titleBar.title = resolvedTitle
        optionsSheet?.heading = resolvedTitle
        onTitleChange?()
    }

    /// Re-asks the content for its title-bar controls. Content whose controls
    /// depend on its own state calls this by changing, and the pane replaces
    /// the whole array rather than diffing it.
    public func refreshAccessories() {
        titleBar.accessoryViews =
            (contentViewController as? PaneAccessoryProviding)?.makePaneAccessoryViews() ?? []
    }

    /// Re-asks the host which edges are legal. The answer changes whenever the
    /// layout around this pane does, which is why it is a call and not a
    /// property set once.
    public func refreshControlAvailability() {
        guard isViewLoaded else { return }
        let edges = host?.availableMinimizeEdges(for: self) ?? []
        titleBar.controls.canMinimize = !edges.isEmpty
    }

    // MARK: - State the host hands back

    /// How thick this pane is once it is minimized along `edge` — the rail's
    /// width for a side, the title bar's height for a top or bottom. The
    /// border allowance is counted twice because it sits on both sides of
    /// whichever chrome is left showing.
    ///
    /// The host pins the pane to this. It is a method on the pane because the
    /// answer is a fact about the pane's own chrome: a subclass with a taller
    /// title bar overrides `contentInset`, and this follows.
    public func minimizedThickness(for edge: PaneEdge) -> CGFloat {
        let chrome = edge.isHorizontal
            ? PaneMinimizedStripView.thickness
            : PaneTitleBarView.height
        return chrome + contentInset * 2
    }

    /// Called by the host once it has actually minimized (or restored) this
    /// pane. Never called from a click: a click is a request.
    public func setMinimized(to edge: PaneEdge?) {
        minimizedEdge = edge
        stateStore.setPaneStateValue(edge?.rawValue, forKey: PaneStateKey.minimizeEdge)
        applyMinimizedAppearance()
    }

    public func setZoomed(_ zoomed: Bool) {
        isZoomed = zoomed
        titleBar.controls.isZoomed = zoomed
        stateStore.setPaneStateValue(zoomed ? "1" : nil, forKey: PaneStateKey.zoomed)
    }

    // MARK: - Persistence

    /// What the store says this pane was left as. The host reads these to work
    /// out what the *tree* has to do about it — collapsing a split item,
    /// collapsing an ancestor chain — which is not this class's business.
    public var persistedMinimizeEdge: PaneEdge? {
        stateStore.paneStateValue(forKey: PaneStateKey.minimizeEdge).flatMap(PaneEdge.init(rawValue:))
    }

    public var persistedZoomed: Bool {
        stateStore.paneStateValue(forKey: PaneStateKey.zoomed) == "1"
    }

    /// A value that no longer parses — a key written by an older build, or a
    /// hand-edited row — is treated as absent rather than as a reason to stop.
    /// The cost of being wrong is a pane that opens whole.
    private func restorePersistedState() {
        if let edge = persistedMinimizeEdge {
            minimizedEdge = edge
            applyMinimizedAppearance()
        }
        if persistedZoomed {
            isZoomed = true
            titleBar.controls.isZoomed = true
        }
    }

    // MARK: - Appearance

    /// The content's four pins to `contentContainer`, on or off together.
    /// Nothing to do for a pane whose content view controller declined to
    /// exist — there is no content to pin.
    private func setContentEdgeConstraints(active: Bool) {
        guard let edges = contentEdgeConstraints else { return }
        let all = [edges.top, edges.leading, edges.bottom, edges.trailing]
        if active {
            NSLayoutConstraint.activate(all)
        } else {
            NSLayoutConstraint.deactivate(all)
        }
    }

    /// The three shapes a pane can be in, in one place, so they cannot disagree.
    ///
    /// - whole: title bar over content.
    /// - minimized top or bottom: the title bar, and nothing under it.
    /// - minimized leading or trailing: a rail one icon wide, instead of both.
    ///
    /// Does nothing until the view exists, the same guard
    /// `refreshControlAvailability()` makes and for a sharper reason: every
    /// branch below touches `view`, so on an unloaded pane this method *loads*
    /// it — and `viewDidLoad` ends by calling `restorePersistedState()`, which
    /// re-enters here. The rail built by the inner call is the one
    /// `minimizedStrip` ends up holding; the outer call then adds a second
    /// rail to the same view that nothing tracks and nothing can remove.
    /// `minimizedEdge` and the store are already written by the time this is
    /// called, so skipping is lossless: whenever the view does load,
    /// `restorePersistedState()` applies exactly this.
    private func applyMinimizedAppearance() {
        guard isViewLoaded else { return }
        titleBar.controls.isMinimized = minimizedEdge != nil
        // Only the rail is narrower than the title bar; every other shape shows
        // it, so it goes back to spanning the pane.
        titleBarTrailing?.isActive = !(minimizedEdge?.isHorizontal ?? false)

        guard let edge = minimizedEdge else {
            titleBar.isHidden = false
            contentContainer.isHidden = false
            contentViewController?.view.isHidden = false
            setContentEdgeConstraints(active: true)
            minimizedStrip?.removeFromSuperview()
            minimizedStrip = nil
            builtStripEdge = nil
            return
        }

        contentContainer.isHidden = true
        contentViewController?.view.isHidden = true
        // Hidden is not un-laid-out: AppKit still solves for a hidden view, so
        // content with its own minimum size goes on demanding it from a
        // container the host has just squeezed to a rail's width, and the
        // engine breaks whichever constraint it likes to get out. Releasing
        // the four pins takes the content out of the pane's layout entirely
        // while it has no space to be in, and `setMinimized(to: nil)` puts
        // them back before it is visible again.
        setContentEdgeConstraints(active: false)

        guard edge.isHorizontal else {
            titleBar.isHidden = false
            minimizedStrip?.removeFromSuperview()
            minimizedStrip = nil
            builtStripEdge = nil
            return
        }

        titleBar.isHidden = true
        if builtStripEdge != edge {
            minimizedStrip?.removeFromSuperview()
            minimizedStrip = nil
            builtStripEdge = nil
        }
        if minimizedStrip == nil {
            let representing = contentViewController as? PaneMinimizedRepresenting
            let strip = PaneMinimizedStripView(
                edge: edge,
                symbolName: representing?.paneMinimizedSymbolName ?? PaneMinimizedStripView.defaultSymbolName,
                tooltip: representing?.paneMinimizedTooltip ?? resolvedTitle
            )
            strip.onRestore = { [weak self] in
                guard let self else { return }
                host?.paneDidRequestRestore(self)
            }
            view.addSubview(strip)
            // The strip owns its own 28pt width. Pinning both sides as well
            // makes that width unsatisfiable at every container size but one,
            // so the pane docks the rail to the edge it minimized toward and
            // lets the rail's own width settle the other side. At the
            // thickness the host pins a minimized split item to, the two
            // agree exactly; at any other width the rail hugs its edge
            // instead of fighting.
            let dockedSide = edge == .leading
                ? strip.leadingAnchor.constraint(equalTo: view.leadingAnchor)
                : strip.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            NSLayoutConstraint.activate([
                strip.topAnchor.constraint(equalTo: view.topAnchor),
                strip.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                dockedSide
            ])
            minimizedStrip = strip
            builtStripEdge = edge
        }
    }
}
