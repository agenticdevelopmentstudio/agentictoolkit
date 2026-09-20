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

    /// Fired when the ticked set changes, with the ids that are now **hidden** —
    /// the same vocabulary ``ConversationsSessionFilter`` stores, so the host
    /// hands it straight over without inverting anything.
    public var onHiddenChanged: ((Set<String>) -> Void)?

    /// Every session in the feed, newest roster wins. Setting it keeps the
    /// reader's sort, filter text and scroll position.
    public var sessions: [Session] = [] {
        didSet {
            guard sessions != oldValue else { return }
            reload()
        }
    }

    /// The sessions the feed is not drawing.
    public private(set) var hidden: Set<String> = []

    /// Deliberately **not** a `ThemedTableView`: that type exists to paint a
    /// palette plane over the system's `controlBackgroundColor`, and here there
    /// is nothing to paint over — the sidebar's own material is the backdrop,
    /// and a filled table hides the inset panel it is drawn inside.
    private let table = NSTableView(frame: .zero)
    private let scrollView = ThemedScrollView(frame: .zero)
    private let filterField = ThemedSearchField(placeholder: "Filter")
    private let selectionMenuButton = NSPopUpButton(frame: .zero, pullsDown: true)

    /// The rows on screen: `sessions` narrowed by the filter text, then sorted.
    /// Held rather than recomputed per delegate callback because "the visible
    /// list" is also what Select All and Unselect All act on, and the two must
    /// be the same list or the menu lies.
    private var visible: [Session] = []

    private var filterText: String = ""
    private var sortAscending = true

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
        if isViewLoaded { table.reloadData() }
    }

    /// Ticks every row **in the visible list**, leaving anything the filter has
    /// narrowed away exactly as it was.
    ///
    /// Scoped to the visible list because that is the only reading that survives
    /// a filter: "all" typed into a search field means all of what you can see.
    /// A Select All that quietly reached past the filter would undo a reader's
    /// careful narrowing with one keystroke, and there would be no way to tell
    /// from the screen that it had.
    @objc public func selectAllVisible() {
        apply(hidden.subtracting(visible.map(\.id)))
    }

    /// Unticks every row in the visible list, on the same terms.
    @objc public func unselectAllVisible() {
        apply(hidden.union(visible.map(\.id)))
    }

    private func apply(_ ids: Set<String>) {
        guard ids != hidden else { return }
        hidden = ids
        table.reloadData()
        onHiddenChanged?(hidden)
    }

    private func toggle(_ id: String) {
        apply(hidden.contains(id) ? hidden.subtracting([id]) : hidden.union([id]))
    }

    // MARK: - View

    public override func loadView() {
        // Unpainted itself: the panel below is what the reader sees, and the
        // container is only here to catch ⌘A and to give the panel its margin.
        let container = ShelfContainerView()
        container.onCommandA = { [weak self] extend in
            guard let self, self.ownsFirstResponder else { return false }
            if extend { self.unselectAllVisible() } else { self.selectAllVisible() }
            return true
        }

        // The System Settings outline: a rounded panel of sidebar material,
        // floating inside the window rather than filling a column of it. The
        // system does not hand this out — `NSSplitViewItem`'s own sidebar
        // backdrop is full-bleed and square — so the material is the system's
        // and only the shape is ours.
        let panel = NSVisualEffectView()
        panel.material = .sidebar
        panel.blendingMode = .behindWindow
        panel.state = .followsWindowActiveState
        panel.wantsLayer = true
        panel.layer?.cornerRadius = Self.panelCornerRadius
        panel.layer?.cornerCurve = .continuous
        panel.layer?.masksToBounds = true
        panel.translatesAutoresizingMaskIntoConstraints = false

        let filterBar = makeFilterBar()
        filterBar.translatesAutoresizingMaskIntoConstraints = false

        configureTable()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(panel)
        panel.addSubview(filterBar)
        panel.addSubview(scrollView)

        let inset = Self.panelInset
        NSLayoutConstraint.activate([
            // Inset on all four sides, including the top: the panel runs up
            // behind the traffic lights exactly as System Settings' does, which
            // is why the window's titlebar is transparent.
            panel.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            panel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            panel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset),

            // The **safe area**, not the panel's own top: the panel runs under
            // the traffic lights, and a filter field pinned to its top edge
            // lands beneath the close button. AppKit insets the safe area past
            // them, so this is the first line that is free to be clicked.
            filterBar.topAnchor.constraint(
                equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 8),
            filterBar.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            filterBar.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -8),

            // No rule between the field and the list: a full-width hairline
            // drawn across a rounded panel cuts it in half rather than
            // separating anything.
            scrollView.topAnchor.constraint(equalTo: filterBar.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        ])

        self.view = container
        reload()
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
        // The header is the sort control. A sortable table with its header
        // hidden is a table that cannot be sorted by anyone who did not read
        // the source.
        name.sortDescriptorPrototype = NSSortDescriptor(key: Column.name.rawValue, ascending: true)
        table.addTableColumn(name)

        table.dataSource = self
        table.delegate = self
        table.style = .sourceList
        table.backgroundColor = .clear
        table.usesAlternatingRowBackgroundColors = false
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.rowSizeStyle = .custom
        table.usesAutomaticRowHeights = true
        table.sortDescriptors = [NSSortDescriptor(key: Column.name.rawValue, ascending: true)]
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

    // MARK: - Contents

    /// Recomputes the visible list from the roster, the filter text and the
    /// sort, then redraws. The single place any of the three takes effect.
    private func reload() {
        let needle = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = needle.isEmpty
            ? sessions
            : sessions.filter { $0.searchText.localizedCaseInsensitiveContains(needle) }
        visible = matched.sorted { lhs, rhs in
            let order = lhs.name.localizedStandardCompare(rhs.name)
            // A stable tiebreak on the id, so two sessions sharing a name do not
            // swap places every time the roster is re-read.
            let resolved = order == .orderedSame ? lhs.id.compare(rhs.id) : order
            return sortAscending ? resolved == .orderedAscending : resolved == .orderedDescending
        }
        guard isViewLoaded else { return }
        table.reloadData()
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
        toggle(visible[row].id)
    }

    // MARK: - NSTableViewDataSource / Delegate

    public func numberOfRows(in tableView: NSTableView) -> Int { visible.count }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ThemedTableRowView()
    }

    public func tableView(
        _ tableView: NSTableView,
        sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
    ) {
        sortAscending = tableView.sortDescriptors.first?.ascending ?? true
        reload()
    }

    public func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard visible.indices.contains(row), let column = tableColumn else { return nil }
        let session = visible[row]
        switch column.identifier {
        case Column.check: return checkCell(shown: !hidden.contains(session.id))
        case Column.name: return nameCell(for: session)
        default: return nil
        }
    }

    /// A checkmark, or the space where one would be. Deliberately an image view
    /// and not a control: the row is what takes the click, so a button here
    /// would only add a second, smaller target that does the same thing.
    private func checkCell(shown: Bool) -> NSView {
        let image = NSImageView()
        image.imageScaling = .scaleNone
        image.image = shown
            ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Shown")
            : nil
        image.setAccessibilityValue(shown ? "shown" : "hidden")
        image.observeTheme { view, palette in
            view.contentTintColor = palette.nsColor(.accent)
        }
        return image
    }

    /// The session's name over its project and branch — the same two crumbs the
    /// feed's rows carry, drawn small underneath so the name stays the thing
    /// you read down the column.
    private func nameCell(for session: Session) -> NSView {
        let name = ThemedLabel(string: session.name, role: .primaryText, textRole: .body)
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [name])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 4)
        // The table sets a cell view's frame itself, so the root of one keeps
        // its autoresizing translation. Turning it off here left the stack at
        // its intrinsic width — the width of the longest session name — and the
        // column drew a row that ran off its own right edge, mid-glyph, with
        // neither label reaching the truncation it had asked for.
        stack.translatesAutoresizingMaskIntoConstraints = true

        let crumbs = session.context.joined(separator: " · ")
        if !crumbs.isEmpty {
            let context = ThemedLabel(string: crumbs, role: .secondaryText, textRole: .caption)
            context.lineBreakMode = .byTruncatingHead
            context.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(context)
        }
        // And a label only truncates if it is willing to be narrower than its
        // text. Both of these would rather overflow the column than shrink.
        for label in stack.arrangedSubviews {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        return stack
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
