import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS

/// The Conversations window's left shelf: every session the feed knows about,
/// in a table sorted by name, each row ticked when the feed is drawing it.
///
/// It is a roster, not a picker — the rows come from what the feed actually
/// contains (``ConversationsSessionFilter``), so a session that starts talking
/// arrives here on its own, already ticked, and nothing has to be configured
/// for it. Untick it and its messages leave the timeline.
///
/// The checkmark is a **column**, not a checkbox control: every row reserves the
/// same leading width, and an unticked row draws blank there. That is what makes
/// the ticks scannable down the edge of the list — a column of controls, each
/// drawing its own frame, gives you a column of boxes to read instead of a
/// column of answers.
@MainActor
public final class ConversationsShelfViewController: NSViewController,
                                                     NSTableViewDataSource,
                                                     NSTableViewDelegate,
                                                     NSSearchFieldDelegate {

    public typealias Session = ConversationsSessionFilter.Session

    /// Accessibility identifiers, which are also how the UI harness addresses
    /// these controls. Public because a test outside this framework has no
    /// other way to name them.
    public enum AXID {
        public static let table = "conversations.shelf.table"
        public static let filterField = "conversations.shelf.filter"
        public static let selectionMenu = "conversations.shelf.selection-menu"
    }

    /// Column identifiers. The sort is driven off the name column's prototype,
    /// so the identifier is the sort key too.
    private enum Column {
        static let check = NSUserInterfaceItemIdentifier("check")
        static let name = NSUserInterfaceItemIdentifier("name")
    }

    /// Where the rows' activity glyphs come from — the same seam the Sessions
    /// window reads, so both windows agree about what a session is doing rather
    /// than each deriving it from whatever it happens to have.
    ///
    /// Optional, and nil is a working shelf with no glyphs: the roster is built
    /// out of what was *said* (``ConversationsSessionFilter``), which carries no
    /// live state at all, so a host that cannot answer the question simply does
    /// not.
    ///
    /// The source is only watched while ``watchesActivity`` is on — the window
    /// turns it on when it appears and off when it goes away, so a window built
    /// at launch and never opened polls nothing.
    public var activitySource: SessionWatcher.SessionListSource? {
        didSet {
            guard activitySource !== oldValue else { return }
            if watchesActivity { oldValue?.stopObserving() }
            activity = [:]
            if watchesActivity { startWatching() }
        }
    }

    /// Whether ``activitySource`` is being watched. Off by default; the host's
    /// window switches it on while it is on screen.
    public var watchesActivity = false {
        didSet {
            guard watchesActivity != oldValue else { return }
            if watchesActivity {
                startWatching()
            } else {
                activitySource?.stopObserving()
            }
        }
    }

    private func startWatching() {
        guard let source = activitySource else { return }
        // The source decides its own cadence; this just says it is being
        // watched. Its first read is what fills the cache, so the immediate
        // read below is not an optimisation — without it the shelf draws no
        // glyphs until the source's first poll happens to change something.
        source.startObserving { [weak self] in
            Task { @MainActor in await self?.readActivity(from: source) }
        }
        Task { @MainActor [weak self] in await self?.readActivity(from: source) }
    }

    /// What each session is doing, by id. Written by the poll below, and
    /// settable directly by a host that already has the answer (or by a test).
    public var activity: [String: SessionWatcher.SessionWatcherActivity] = [:] {
        didSet {
            guard activity != oldValue else { return }
            repaintActivity()
            onActivityChanged?(activity)
        }
    }

    /// Fired when ``activity`` changes, so a host can show the same fact
    /// somewhere else — the feed's status line — without polling a second time.
    public var onActivityChanged: (([String: SessionWatcher.SessionWatcherActivity]) -> Void)?

    /// The glyphs currently on screen, held **weakly**: the table owns its cells
    /// and discards them when it likes, and a poll landing between a discard and
    /// the next reload must update nothing rather than resurrect a dead row.
    private final class WeakIcon {
        weak var view: SessionWatcher.SessionWatcherActivityIconView?
        init(_ view: SessionWatcher.SessionWatcherActivityIconView) { self.view = view }
    }
    private var activityViews: [String: WeakIcon] = [:]

    /// Fired when the ticked set changes, with the ids that are now **hidden** —
    /// the same vocabulary ``ConversationsSessionFilter`` stores, so the host
    /// hands it straight over without inverting anything.
    public var onHiddenChanged: ((Set<String>) -> Void)?

    /// Fired when single mode's pick moves, with the session now shown.
    ///
    /// A channel of its own rather than a hidden set: the hidden set is the
    /// reader's multi-mode ticks, and expressing a pick as "everything else
    /// hidden" overwrote them — a visit to single mode came back to one tick.
    public var onSoloChanged: ((String?) -> Void)?

    /// Whether the shelf picks one session at a time or any number of them.
    ///
    /// Switching to ``ConversationsSelectionMode/single`` keeps the session
    /// last picked, or else the first one showing, so the change reads as a
    /// narrowing of what is on screen rather than as a jump to something
    /// arbitrary. The ticks are never touched by it: single mode is a way of
    /// *looking* at the roster, and passing through it must not cost the
    /// selection the reader built.
    public var selectionMode: ConversationsSelectionMode = .multi {
        didSet {
            guard selectionMode != oldValue else { return }
            // Single mode always has a row picked, so there is nothing for an
            // empty selection to mean and no way to reach one.
            table.allowsEmptySelection = selectionMode == .multi
            // Select All / Unselect All are multi-mode answers; see
            // `selectAllVisible()`.
            selectionMenuButton.isEnabled = selectionMode == .multi
            // The check column draws a different answer in each mode.
            if isViewLoaded { reloadRows() }
            if selectionMode == .single {
                adoptSolo()
            } else {
                syncTableSelection()
            }
        }
    }

    /// In single mode, the one session being shown. Kept across a visit to
    /// multi mode, so coming back lands on the same conversation.
    ///
    /// Held rather than derived from the hidden set, because the roster changes
    /// under it: a session that says nothing for a while falls off the page, and
    /// "the first one not hidden" would then quietly become a different
    /// conversation than the one the reader picked.
    public private(set) var soloID: String?

    /// Whether the selection is being moved by the shelf rather than by the
    /// reader — see ``reloadRows()``.
    private var isSettlingSelection = false

    /// Every session in the feed, newest roster wins. Setting it keeps the
    /// reader's sort, filter text and scroll position.
    public var sessions: [Session] = [] {
        didSet {
            guard sessions != oldValue else { return }
            reload()
            // The first roster is what a restored pick is checked against, and
            // a pick whose session has gone needs replacing.
            if selectionMode == .single { adoptSolo() }
        }
    }

    /// The sessions the feed is not drawing.
    public private(set) var hidden: Set<String> = []

    /// Deliberately **not** a `ThemedTableView`: that type paints a palette
    /// plane of its own, and here there is already one underneath — the panel.
    /// A second fill on top of it would hide the inset the panel exists to
    /// draw, and would be the same colour anyway.
    private let table = NSTableView(frame: .zero)
    private let scrollView = ThemedScrollView(frame: .zero)
    private let filterField = ThemedSearchField(placeholder: "Filter")
    private let selectionMenuButton = NSPopUpButton(frame: .zero, pullsDown: true)

    /// The filter box, for a host wiring a window-wide Tab order — see
    /// ``KeyViewLoop``. The shelf is usually collapsed, and a collapsed pane
    /// hides its contents rather than disabling them, which the loop reads.
    public var filterTextField: NSView {
        loadViewIfNeeded()
        return filterField
    }

    /// The list's backdrop: a themed panel, not the system's sidebar material.
    /// Sidebar material is drawn by the appearance and reaches no theme, so a
    /// window in a custom theme had a grey-blue plane down its left that
    /// belonged to none of it.
    private let panel = ThemedBox(
        fill: .surface,
        stroke: .border,
        cornerRadius: ConversationsShelfViewController.panelCornerRadius)

    /// The sort control, in place of the table's own header: an
    /// `NSTableHeaderView` is system-drawn to the last pixel, and every other
    /// table in this toolkit sets `headerView = nil` for exactly that reason.
    private let sortButton = NSButton(frame: .zero)

    /// The rows on screen: `sessions` narrowed by the filter text, then sorted.
    /// Held rather than recomputed per delegate callback because "the visible
    /// list" is also what Select All and Unselect All act on, and the two must
    /// be the same list or the menu lies.
    private var visible: [Session] = []

    private var filterText: String = ""
    private var sortAscending = true

    /// The palette the sort header was last painted with, so a click can
    /// repaint it without waiting for a theme change to hand one over.
    private var sortPalette: SemanticPalette = ThemePaletteObserver.currentPalette

    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    // MARK: - Selection

    /// Whether the keyboard is currently somewhere inside the shelf — its table
    /// or its filter field. What decides whether ⌘A is ours or the feed's.
    private var ownsFirstResponder: Bool {
        guard isViewLoaded, let responder = view.window?.firstResponder else { return false }
        var candidate = responder as? NSView
        if candidate == nil, let editor = responder as? NSText {
            candidate = editor.delegate as? NSView
        }
        // A field editor's superview chain already runs through the field it is
        // editing, so walking up from either lands in the shelf.
        var node = candidate
        while let current = node {
            if current === view { return true }
            node = current.superview
        }
        return false
    }

    /// Replaces the hidden set without telling the host about it — for
    /// restoring a remembered one, where the host already knows.
    public func setHidden(_ ids: Set<String>) {
        guard ids != hidden else { return }
        hidden = ids
        if isViewLoaded { reloadRows() }
    }

    /// Ticks every row **in the visible list**, leaving anything the filter has
    /// narrowed away exactly as it was.
    ///
    /// Scoped to the visible list because that is the only reading that survives
    /// a filter: "all" typed into a search field means all of what you can see.
    /// A Select All that quietly reached past the filter would undo a reader's
    /// careful narrowing with one keystroke, and there would be no way to tell
    /// from the screen that it had.
    ///
    /// Both this and ``unselectAllVisible()`` do nothing in single mode: "all"
    /// is the one answer that mode has no way to draw, and an unselect-all would
    /// leave it with no conversation at all.
    @objc public func selectAllVisible() {
        guard selectionMode == .multi else { return }
        apply(hidden.subtracting(visible.map(\.id)))
    }

    /// Unticks every row in the visible list, on the same terms.
    @objc public func unselectAllVisible() {
        guard selectionMode == .multi else { return }
        apply(hidden.union(visible.map(\.id)))
    }

    /// Replaces the single-mode pick without telling the host — for restoring
    /// a remembered one. Checked against the roster when the roster arrives,
    /// not here: at restore time there is no roster yet, and a pick refused
    /// for that would never survive a relaunch.
    public func setSolo(_ id: String?) {
        guard id != soloID else { return }
        let old = soloID
        soloID = id
        reloadCheckRows(for: [old, id].compactMap { $0 })
        syncTableSelection()
    }

    private func apply(_ ids: Set<String>) {
        guard ids != hidden else { return }
        let changed = ids.symmetricDifference(hidden)
        hidden = ids
        reloadCheckRows(for: changed)
        onHiddenChanged?(hidden)
    }

    /// Redraws the check column of the rows for `ids` and nothing else.
    ///
    /// A tick is one cell. Rebuilding every row for it restarted every
    /// activity glyph's animation and dropped every row's hover state, on a
    /// click that changed one mark.
    private func reloadCheckRows(for ids: some Sequence<String>) {
        guard isViewLoaded else { return }
        let wanted = Set(ids)
        let rows = IndexSet(visible.indices.filter { wanted.contains(visible[$0].id) })
        guard !rows.isEmpty,
              let column = table.tableColumns.firstIndex(where: { $0.identifier == Column.check })
        else { return }
        settlingSelection {
            table.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: column))
        }
    }

    /// Redraws the list.
    ///
    /// Every row is rebuilt, so the table drops its highlight — and since single
    /// mode disallows an empty selection, AppKit immediately puts one back on
    /// row 0, before ``syncTableSelection()`` has restored the pick. That is the
    /// shelf redrawing itself, never the reader moving, so the selection change
    /// it raises is one ``tableViewSelectionDidChange(_:)`` has to sit out;
    /// otherwise picking the third row would redraw, be told the first row was
    /// picked, and land back where it started.
    private func reloadRows() {
        settlingSelection { table.reloadData() }
    }

    /// Runs `body` with the shelf's own selection changes marked as such.
    /// Nested because a redraw restores the highlight, which redraws nothing but
    /// is equally not the reader.
    private func settlingSelection(_ body: () -> Void) {
        let wasSettling = isSettlingSelection
        isSettlingSelection = true
        defer { isSettlingSelection = wasSettling }
        body()
    }

    private func toggle(_ id: String) {
        apply(hidden.contains(id) ? hidden.subtracting([id]) : hidden.union([id]))
    }

    // MARK: - Single mode

    /// Makes `id` the one shown session. A click in single mode *replaces* the
    /// pick rather than toggling it: unticking the only ticked row would leave
    /// the feed empty, and an empty feed is not a state this mode has a way back
    /// out of except by clicking something else anyway.
    private func pick(_ id: String) {
        guard id != soloID else { return syncTableSelection() }
        setSolo(id)
        onSoloChanged?(id)
    }

    /// Settles the single-mode invariant — one session picked — keeping the
    /// current pick if it is still in the roster.
    ///
    /// A no-op while the roster is empty, and that is load-bearing: the host
    /// restores a remembered pick before the first page has been read, and
    /// checking it against zero sessions would throw it away.
    private func adoptSolo() {
        guard selectionMode == .single, !sessions.isEmpty else { return }
        if let soloID, sessions.contains(where: { $0.id == soloID }) {
            return syncTableSelection()
        }
        let next = visible.first { !hidden.contains($0.id) }?.id
            ?? visible.first?.id
            ?? sessions.first?.id
        guard let next else { return }
        pick(next)
    }

    /// Moves the pick `delta` rows down the visible list (negative is up).
    ///
    /// Stops at the ends rather than wrapping: the keystroke is one a reader
    /// holds down to walk the list, and a wrap turns arriving at the bottom into
    /// a jump back to the top that reads as the selection having been lost.
    /// Returns whether it moved, so a key handler can let the keystroke fall
    /// through when there was nowhere to go.
    @discardableResult
    public func moveSelection(by delta: Int) -> Bool {
        guard selectionMode == .single, !visible.isEmpty else { return false }
        let current = soloID.flatMap { id in visible.firstIndex { $0.id == id } }
        // With nothing picked yet, the first press picks the first row rather
        // than moving off an index that does not exist.
        let target = current.map { $0 + delta } ?? 0
        let next = min(max(target, 0), visible.count - 1)
        guard next != current else { return false }
        pick(visible[next].id)
        return true
    }

    /// Every visible row but the pick, nearest the pick first — below, above,
    /// two below, two above, and so on out to the ends. The order a reader
    /// walking the list with ``moveSelection(by:)`` can reach them in, which is
    /// the order a prefetch should read them in. With no pick, the list from
    /// the top, where the first press lands.
    public func idsByDistanceFromSolo() -> [String] {
        guard let center = soloID.flatMap({ id in visible.firstIndex { $0.id == id } }) else {
            return visible.map(\.id)
        }
        var ids: [String] = []
        ids.reserveCapacity(visible.count - 1)
        for step in 1..<max(visible.count, 1) {
            for index in [center + step, center - step] where visible.indices.contains(index) {
                ids.append(visible[index].id)
            }
        }
        return ids
    }

    /// In single mode the picked row is the table's selected row too, so the
    /// reader can see what the arrow keys just moved. In multi mode there is no
    /// such thing as *the* row, and a highlight on one of several ticked
    /// sessions would say there is.
    private func syncTableSelection() {
        guard isViewLoaded else { return }
        settlingSelection {
            guard selectionMode == .single,
                  let soloID,
                  let row = visible.firstIndex(where: { $0.id == soloID })
            else {
                // `deselectAll` does nothing to a table that disallows an
                // empty selection — which single mode's does, and the pick can
                // be filtered out of view there. Allowed for the one call.
                let allowsEmpty = table.allowsEmptySelection
                table.allowsEmptySelection = true
                table.deselectAll(nil)
                table.allowsEmptySelection = allowsEmpty
                return
            }
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
    }

    // MARK: - View

    public override func loadView() {
        // Unpainted itself: the panel below is what the reader sees, and the
        // container is only here to catch ⌘A and to give the panel its margin.
        let container = ShelfContainerView()
        container.onCommandA = { [weak self] extend in
            guard let self, self.ownsFirstResponder else { return false }
            guard self.selectionMode == .multi else { return false }
            if extend { self.unselectAllVisible() } else { self.selectAllVisible() }
            return true
        }

        // The System Settings outline, in the theme's colours: a rounded panel
        // floating inside the window rather than filling a column of it.
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.layer?.cornerCurve = .continuous
        // Rows run the full width of the panel, so without this the top and
        // bottom ones square off its corners from the inside.
        panel.layer?.masksToBounds = true

        let filterBar = makeFilterBar()
        filterBar.translatesAutoresizingMaskIntoConstraints = false

        let header = makeSortHeader()
        header.translatesAutoresizingMaskIntoConstraints = false

        configureTable()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(panel)
        panel.addSubview(filterBar)
        panel.addSubview(header)
        panel.addSubview(scrollView)

        let inset = Self.panelInset
        // A collapsing split pane is animated to **zero** width, and every
        // horizontal constraint in here is one AppKit would have to break to
        // get there — which it does, loudly, and the contents jump sideways
        // for the length of the animation. Below required, they simply give,
        // and the panel slides out as one piece.
        let horizontal = [
            panel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            panel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            filterBar.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            filterBar.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -8),

            header.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            header.trailingAnchor.constraint(lessThanOrEqualTo: panel.trailingAnchor, constant: -8),

            scrollView.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: panel.trailingAnchor)
        ]
        for constraint in horizontal { constraint.priority = .defaultHigh }

        NSLayoutConstraint.activate(horizontal + [
            // Inset top and bottom: the panel runs up behind the traffic lights
            // exactly as System Settings' does, which is why the window's
            // titlebar is transparent.
            panel.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            panel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset),

            // The **safe area**, not the panel's own top: the panel runs under
            // the traffic lights, and a filter field pinned to its top edge
            // lands beneath the close button. AppKit insets the safe area past
            // them, so this is the first line that is free to be clicked.
            filterBar.topAnchor.constraint(
                equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 8),

            header.topAnchor.constraint(equalTo: filterBar.bottomAnchor, constant: 10),

            // No rule between the header and the list: a full-width hairline
            // drawn across a rounded panel cuts it in half rather than
            // separating anything.
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        ])

        // The width the shelf opens at, and the reason it is a constraint
        // rather than a divider position: it is what a split view asks the pane
        // for, and it loses to the reader's own drag the moment there is one.
        let width = container.widthAnchor.constraint(equalToConstant: Self.preferredWidth)
        width.priority = .defaultLow
        width.isActive = true

        self.view = container
        reload()
    }

    /// The sort control the table's own header would have been. One column, so
    /// one button: it names what the list is sorted by and which way, and
    /// clicking it turns the sort around.
    private func makeSortHeader() -> NSView {
        sortButton.isBordered = false
        sortButton.bezelStyle = .regularSquare
        sortButton.focusRingType = .none
        sortButton.imagePosition = .imageTrailing
        sortButton.target = self
        sortButton.action = #selector(toggleSortDirection)
        sortButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // Registered once, here: `observeTheme` appends an observer per call,
        // so painting from inside it would stack up a new one on every click.
        sortButton.observeTheme { [weak self] button, palette in
            self?.paintSortHeader(button, palette: palette)
        }
        updateSortHeader()
        return sortButton
    }

    @objc private func toggleSortDirection() {
        sortAscending.toggle()
        updateSortHeader()
        reload()
    }

    /// Repaints the sort button from the palette and the current direction — an
    /// attributed title freezes whatever palette drew it, so both a theme
    /// change and a click come back through here.
    private func paintSortHeader(_ button: NSButton, palette: SemanticPalette) {
        sortPalette = palette
        button.image = NSImage(
            systemSymbolName: sortAscending ? "chevron.up" : "chevron.down",
            accessibilityDescription: sortAscending ? "Ascending" : "Descending")
        button.symbolConfiguration = NSImage.SymbolConfiguration(scale: .small)
        button.contentTintColor = palette.nsColor(.secondaryText)
        button.toolTip = sortAscending ? "Sorted A to Z — click to reverse"
                                       : "Sorted Z to A — click to reverse"
        button.attributedTitle = NSAttributedString(string: "Session", attributes: [
            .foregroundColor: palette.nsColor(.secondaryText),
            .font: palette.font(.caption)
        ])
    }

    private func updateSortHeader() {
        paintSortHeader(sortButton, palette: sortPalette)
    }

    /// The filter toolbar: a field that narrows the list, and beside it the
    /// pull-down that acts on whatever the field left.
    private func makeFilterBar() -> NSView {
        filterField.delegate = self
        filterField.sendsWholeSearchString = false
        filterField.sendsSearchStringImmediately = true
        filterField.target = self
        filterField.action = #selector(filterChanged)
        filterField.translatesAutoresizingMaskIntoConstraints = false
        _ = filterField.accessibilityID(AXID.filterField)

        // A pull-down, so item 0 is the button's own face and never chosen —
        // the same idiom `MultiChoiceFilterButton` uses, and the reason the
        // menu can carry an ellipsis glyph without an item going missing.
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""))
        let selectAll = NSMenuItem(
            title: "Select All", action: #selector(selectAllVisible), keyEquivalent: "a")
        selectAll.target = self
        menu.addItem(selectAll)
        let unselectAll = NSMenuItem(
            title: "Unselect All", action: #selector(unselectAllVisible), keyEquivalent: "A")
        unselectAll.target = self
        menu.addItem(unselectAll)

        selectionMenuButton.menu = menu
        selectionMenuButton.imagePosition = .imageOnly
        selectionMenuButton.image = NSImage(
            systemSymbolName: "checklist", accessibilityDescription: "Selection")
        selectionMenuButton.bezelStyle = .toolbar
        selectionMenuButton.toolTip = "Select or unselect the sessions shown here"
        selectionMenuButton.translatesAutoresizingMaskIntoConstraints = false
        selectionMenuButton.setContentHuggingPriority(.required, for: .horizontal)
        // A pull-down sizes itself for the widest title in its menu, which here
        // is "Unselect All" — a menu button three times the width of its glyph.
        selectionMenuButton.widthAnchor.constraint(equalToConstant: 32).isActive = true
        selectionMenuButton.isEnabled = selectionMode == .multi
        _ = selectionMenuButton.accessibilityID(AXID.selectionMenu)

        let bar = NSView()
        bar.addSubview(filterField)
        bar.addSubview(selectionMenuButton)
        NSLayoutConstraint.activate([
            filterField.topAnchor.constraint(equalTo: bar.topAnchor),
            filterField.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            filterField.bottomAnchor.constraint(equalTo: bar.bottomAnchor),

            selectionMenuButton.leadingAnchor.constraint(
                equalTo: filterField.trailingAnchor, constant: 6),
            selectionMenuButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            selectionMenuButton.centerYAnchor.constraint(equalTo: filterField.centerYAnchor)
        ])
        return bar
    }

    private func configureTable() {
        let check = NSTableColumn(identifier: Column.check)
        check.title = ""
        check.width = Self.checkColumnWidth
        check.minWidth = Self.checkColumnWidth
        check.maxWidth = Self.checkColumnWidth
        table.addTableColumn(check)

        let name = NSTableColumn(identifier: Column.name)
        name.title = "Session"
        name.resizingMask = .autoresizingMask
        table.addTableColumn(name)

        table.dataSource = self
        table.delegate = self
        table.style = .sourceList
        table.backgroundColor = .clear
        // The sort control is the themed header above the list
        // (`makeSortHeader`). `NSTableHeaderView` is drawn by the system down
        // to its last pixel and reaches no palette, so a themed window got a
        // grey band across the top of the panel.
        table.headerView = nil
        table.usesAlternatingRowBackgroundColors = false
        // Set from the mode, not assumed: a host may set the mode before the
        // view loads, and single mode's table must not be emptied by a click
        // on blank space below the rows.
        table.allowsEmptySelection = selectionMode == .multi
        table.allowsMultipleSelection = false
        table.rowSizeStyle = .custom
        table.usesAutomaticRowHeights = true
        table.target = self
        table.action = #selector(rowClicked)
        _ = table.accessibilityID(AXID.table)
    }

    /// Wide enough for a checkmark and the air around it, and no wider: this
    /// column's whole job is to be the same width on every row.
    private static let checkColumnWidth: CGFloat = 20

    /// The margin between the panel and the window's edges, and the radius of
    /// its corners — the two numbers that are the System Settings outline.
    private static let panelInset: CGFloat = 8
    private static let panelCornerRadius: CGFloat = 10

    /// Air above and below a row's line.
    ///
    /// Generous on purpose: a row here is a place a conversation is happening,
    /// and packed to a single line's leading the list reads as a wall of text
    /// with no way in.
    private static let rowPadding: CGFloat = 7

    /// The header's own metrics — the Sessions window's, read from its row
    /// rather than copied. A shared control drawn at two different sizes is
    /// two controls to a reader, so if the Sessions row's icon changes size,
    /// this one changes with it.
    private typealias HeaderMetrics = SessionWatcher.SessionWatcherRowAppKitView.Metrics

    /// The width the shelf opens at: enough for `project >> branch` to be read
    /// whole, which is the only reason the list is there. Measured against the
    /// real thing — "stenographer >> conversations" at the body size, with the
    /// tick column and the panel's insets in front of it.
    static let preferredWidth: CGFloat = 260

    // MARK: - Contents

    /// Recomputes the visible list from the roster, the filter text and the
    /// sort, then redraws. The single place any of the three takes effect.
    private func reload() {
        let needle = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = needle.isEmpty
            ? sessions
            : sessions.filter { $0.searchText.localizedCaseInsensitiveContains(needle) }
        visible = matched.sorted { lhs, rhs in
            // By what the row *draws*. A list sorted on a title the reader
            // cannot see is a list in no order at all.
            let order = lhs.displayName.localizedStandardCompare(rhs.displayName)
            // A stable tiebreak on the id, so two sessions sharing a name do not
            // swap places every time the roster is re-read.
            let resolved = order == .orderedSame ? lhs.id.compare(rhs.id) : order
            return sortAscending ? resolved == .orderedAscending : resolved == .orderedDescending
        }
        guard isViewLoaded else { return }
        reloadRows()
        // `reloadData` drops the selection, so the single-mode highlight is
        // re-stated here rather than only where the pick changes.
        syncTableSelection()
    }

    // MARK: - Activity

    /// Reads the whole roster's live state in one go and keeps only what the
    /// rows draw.
    ///
    /// Re-checked against ``activitySource`` on the way out because the read is
    /// asynchronous: a source replaced mid-flight would otherwise land its last
    /// answer on top of its successor's first one.
    private func readActivity(from source: SessionWatcher.SessionListSource) async {
        guard let sessions = try? await source.fetchSessions() else { return }
        guard source === activitySource else { return }
        activity = Dictionary(
            sessions.map { ($0.sessionId, $0.activity) },
            // A session id is a session id; if a source hands back two rows for
            // one, the first is as good an answer as the second and neither is
            // worth a crash.
            uniquingKeysWith: { first, _ in first })
    }

    /// Pushes the new state into the glyphs already on screen, rather than
    /// reloading the table. A reload every three seconds would rebuild every
    /// cell, drop the selection and restart each animation from its first
    /// frame — a spinner that keeps jumping back to the top reads as broken.
    private func repaintActivity() {
        for (id, box) in activityViews {
            box.view?.update(activity: activity[id] ?? .idle, isSummarizing: false)
        }
        activityViews = activityViews.filter { $0.value.view != nil }
    }

    /// The row's live-state glyph, which draws nothing at all while the session
    /// is idle — that is ``SessionWatcher/SessionWatcherActivityIconView``'s own
    /// rule, and the reason this is attached unconditionally instead of being
    /// decided here.
    private func activityIcon(for session: Session) -> NSView {
        let icon = SessionWatcher.SessionWatcherActivityIconView(
            activity: activity[session.id] ?? .idle, isSummarizing: false)
        icon.observeTheme { view, palette in view.applyTheme(palette) }
        activityViews[session.id] = WeakIcon(icon)
        return icon
    }

    /// The name crumb, or nothing when the roster had no name to give.
    ///
    /// ``ConversationsSessionFilter/Session`` falls back to the session id when
    /// a session is unnamed, which is the right answer for a row that would
    /// otherwise be blank and the wrong one for the end of a trail — `whippet »
    /// main » 3f7c1a9e-…` is a crumb that says less than the two before it. So
    /// the fallback is used only when it is the whole title.
    private static func trailName(of session: Session) -> String {
        session.name == session.id && !session.context.isEmpty ? "" : session.name
    }

    /// The rows the reader can currently see, in the order they are drawn.
    /// Exposed for the tests that check Select All's scope — the one behaviour
    /// here that is invisible from the outside and easy to get subtly wrong.
    public var visibleSessions: [Session] { visible }

    /// The filter text, as if typed. Setting it re-narrows the list.
    public var filter: String {
        get { filterText }
        set {
            guard newValue != filterText else { return }
            filterText = newValue
            if isViewLoaded { filterField.stringValue = newValue }
            reload()
        }
    }

    @objc private func filterChanged() {
        filterText = filterField.stringValue
        reload()
    }

    public func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === filterField else { return }
        filterChanged()
    }

    @objc private func rowClicked() {
        let row = table.clickedRow
        guard visible.indices.contains(row) else { return }
        switch selectionMode {
        case .multi:  toggle(visible[row].id)
        case .single: pick(visible[row].id)
        }
    }

    // MARK: - NSTableViewDataSource / Delegate

    public func numberOfRows(in tableView: NSTableView) -> Int { visible.count }

    /// The table's highlighted row *is* the pick, so whatever moved the
    /// highlight has moved the pick.
    ///
    /// That is what makes the bare arrow keys work once the list has the
    /// keyboard: ⌘↑ and ⌘↓ are the window-wide command, listened for wherever
    /// the reader is looking, while ↑ and ↓ are the table's own — AppKit was
    /// already moving the highlight with them, and the feed simply did not
    /// follow it. Nothing here is a second implementation of the move; it is
    /// the one place the highlight and the shown conversation are tied
    /// together, which is also why a click needs no special case.
    ///
    /// A redraw moves the highlight too, and that is not the reader — see
    /// ``reloadRows()`` for what is being sat out and why.
    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSettlingSelection,
              selectionMode == .single,
              visible.indices.contains(table.selectedRow),
              visible[table.selectedRow].id != soloID
        else { return }
        pick(visible[table.selectedRow].id)
    }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ThemedTableRowView()
    }

    public func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard visible.indices.contains(row), let column = tableColumn else { return nil }
        let session = visible[row]
        switch column.identifier {
        case Column.check: return checkCell(shown: isChecked(session.id))
        case Column.name: return nameCell(for: session)
        default: return nil
        }
    }

    /// Whether a row carries the checkmark: the pick in single mode, the ticks
    /// in multi mode. The ticks survive single mode untouched, but drawing them
    /// there would say several conversations are showing when one is.
    private func isChecked(_ id: String) -> Bool {
        switch selectionMode {
        case .multi:  return !hidden.contains(id)
        case .single: return id == soloID
        }
    }

    /// A checkmark, or the space where one would be. Deliberately an image view
    /// and not a control: the row is what takes the click, so a button here
    /// would only add a second, smaller target that does the same thing.
    ///
    /// Centred in a container rather than returned bare. The table gives a
    /// bare cell view the row's frame but, with `usesAutomaticRowHeights`, the
    /// image view sizes itself to the symbol and sits at the top of the row —
    /// the tick floated above the row's line instead of beside it.
    private func checkCell(shown: Bool) -> NSView {
        let image = NSImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        image.imageScaling = .scaleNone
        image.image = shown
            ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Shown")
            : nil
        image.setAccessibilityValue(shown ? "shown" : "hidden")
        image.observeTheme { view, palette in
            view.contentTintColor = palette.nsColor(.accent)
        }
        let cell = NSView()
        cell.addSubview(image)
        NSLayoutConstraint.activate([
            image.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    /// `[app] project » branch » name` — the identical trail the Sessions
    /// window lists a session with and the feed heads each bubble with:
    ///
    /// ```
    /// [icon] stenographer » conversations » editing AccountQuotaStore
    /// ```
    ///
    /// Identical is the requirement, not a nicety. A reader moving between the
    /// three windows is looking at one set of conversations, and this row used
    /// to draw two of the three crumbs on one line and the third underneath in
    /// caption grey — so the same session read as `stenographer` here and
    /// `stenographer » conversations` next door, with the name in a different
    /// colour in each. Same view class, different arguments, which is not what
    /// sharing a control is for. The arguments are now the same too: same
    /// crumbs, same icon size, same gap.
    ///
    /// ``SessionBreadcrumbView/Crumbs`` drops the empty segments itself, so a
    /// session with no branch, or none of either, simply draws fewer crumbs —
    /// there is no arrangement of the three to choose between here.
    ///
    /// The icon is always there: ``TerminalAppIcon`` falls back to a generic
    /// terminal glyph for a session that named no application, and a row
    /// without one started its trail 36 points left of every row that had one.
    private func nameCell(for session: Session) -> NSView {
        let header = SessionHeaderView(
            crumbs: .init(context: session.context, name: Self.trailName(of: session)),
            icon: .init(
                appIdentity: session.appIdentity,
                side: HeaderMetrics.iconSide,
                gap: HeaderMetrics.iconToText),
            accessory: activityIcon(for: session),
            accessoryGap: HeaderMetrics.headerToActivity
        )
        header.setAccessibilityLabel(session.displayName)
        // The crumbs truncate to fit the shelf, so the whole trail has to be
        // reachable somewhere.
        header.toolTip = Self.tooltip(for: session)
        // The cell is rebuilt by the table rather than owned by this controller,
        // so it repaints itself instead of waiting to be told.
        header.observeTheme { view, palette in view.applyTheme(palette) }
        // The header owns the row's whole width — the activity glyph rides its
        // far margin, and a header that hugged its text would park the glyph
        // against the name instead of against the column's edge.
        header.setContentHuggingPriority(.init(1), for: .horizontal)

        // The table sets a cell view's frame itself, so the root of one keeps
        // its autoresizing translation. Turning it off left the row at its
        // intrinsic width — the width of the longest session name — and the
        // column drew a row that ran off its own right edge, mid-glyph, with
        // nothing reaching the truncation it had asked for.
        let cell = NSView()
        cell.addSubview(header)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            // Top and bottom, not centred: `usesAutomaticRowHeights` measures a
            // row by the chain of constraints running through its cell, and a
            // centred child leaves that chain open — the row then falls back to
            // a fixed height.
            header.topAnchor.constraint(equalTo: cell.topAnchor, constant: Self.rowPadding),
            header.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -Self.rowPadding)
        ])
        return cell
    }

    /// The whole trail, untruncated — what the row would say given the room.
    static func tooltip(for session: Session) -> String {
        (session.context + [trailName(of: session)])
            .filter { !$0.isEmpty }
            .joined(separator: " » ")
    }
}

/// The shelf's root view, which exists only to catch ⌘A.
///
/// A key equivalent on an `NSPopUpButton`'s menu item fires only while that menu
/// is open — AppKit routes key equivalents through the view hierarchy and the
/// *main* menu, and a popup's menu is in neither. So the shortcut the menu
/// advertises has to be implemented where the shortcut is pressed.
///
/// `performKeyEquivalent` reaches every view in the window regardless of focus,
/// which would make this a window-wide ⌘A. The caller's first-responder check is
/// what keeps it the shelf's: ⌘A in the transcript is still the transcript's.
///
/// It paints **nothing**: the inset panel inside it is the shelf’s backdrop, and
/// a fill here would be the square edge-to-edge plane that panel exists to
/// replace.
private final class ShelfContainerView: NSView {

    /// Handed `true` for ⇧⌘A (unselect) and `false` for ⌘A (select). Returns
    /// whether it took the keystroke.
    var onCommandA: ((_ extend: Bool) -> Bool)?

    init() {
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.subtracting(.shift) == .command,
              event.charactersIgnoringModifiers?.lowercased() == "a",
              let onCommandA
        else { return super.performKeyEquivalent(with: event) }
        return onCommandA(flags.contains(.shift)) || super.performKeyEquivalent(with: event)
    }
}
