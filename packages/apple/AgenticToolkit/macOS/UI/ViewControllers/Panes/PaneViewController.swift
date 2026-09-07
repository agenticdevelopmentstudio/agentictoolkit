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
/// `makeContainerView()`, `makeOptionRows()`, `fallbackTitle`, `contentInset`
/// and `paneAccessibilityIdentifier`. A subclass that overrides none of them
/// still gets a working, empty pane.
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

    /// Internal rather than private so a test can check which edges the picker
    /// was opened with, without opening a popover.
    private(set) var minimizePicker: PaneMinimizePicker?

    private let contentContainer = NSView()
    private var minimizedStrip: PaneMinimizedStripView?
    private var optionsPopover: WindowConfigPopover?

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

    /// The rows in the gear popover. The content's own rows, and — once the
    /// spacing task lands — the frame spacing control above them.
    open func makeOptionRows() -> [NSView] {
        (contentViewController as? PaneOptionsProviding)?.makePaneOptionRows() ?? []
    }

    // MARK: - Loading

    open override func loadView() {
        let container = makeContainerView()
        container.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        container.accessibilityID(paneAccessibilityIdentifier)

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        titleBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleBar)
        container.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            titleBar.topAnchor.constraint(equalTo: container.topAnchor, constant: contentInset),
            titleBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: contentInset),
            container.trailingAnchor.constraint(equalTo: titleBar.trailingAnchor, constant: contentInset),

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
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
            ])
        }

        self.view = container
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        wireControls()
        wireContentCallbacks()
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
        let popover = WindowConfigPopover(
            title: resolvedTitle,
            tooltip: "Pane options",
            // The gear is in ordinary unflipped content here, not in a title
            // bar, so the panel drops from the other edge to land below it.
            preferredEdge: .minY,
            makeControls: { [weak self] in self?.makeOptionRows() ?? [] }
        )
        optionsPopover = popover
        popover.gearButton.accessibilityID("pane.options")
        popover.gearButton.setAccessibilityLabel("Pane Options")
        titleBar.gearView = popover.gearButton
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

    public func refreshTitle() {
        titleBar.title = resolvedTitle
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

    /// The three shapes a pane can be in, in one place, so they cannot disagree.
    ///
    /// - whole: title bar over content.
    /// - minimized top or bottom: the title bar, and nothing under it.
    /// - minimized leading or trailing: a rail one icon wide, instead of both.
    private func applyMinimizedAppearance() {
        titleBar.controls.isMinimized = minimizedEdge != nil

        guard let edge = minimizedEdge else {
            titleBar.isHidden = false
            contentContainer.isHidden = false
            contentViewController?.view.isHidden = false
            minimizedStrip?.removeFromSuperview()
            minimizedStrip = nil
            return
        }

        contentContainer.isHidden = true
        contentViewController?.view.isHidden = true

        guard edge.isHorizontal else {
            titleBar.isHidden = false
            minimizedStrip?.removeFromSuperview()
            minimizedStrip = nil
            return
        }

        titleBar.isHidden = true
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
            NSLayoutConstraint.activate([
                strip.topAnchor.constraint(equalTo: view.topAnchor),
                strip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                strip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                strip.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            minimizedStrip = strip
        }
    }
}
