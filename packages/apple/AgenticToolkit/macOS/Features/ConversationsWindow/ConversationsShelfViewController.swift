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

    /// Deliberately **not** a `ThemedTableView`: that type paints a palette
    /// plane of its own, and here there is already one underneath — the panel.
    /// A second fill on top of it would hide the inset the panel exists to
    /// draw, and would be the same colour anyway.
    private let table = NSTableView(frame: .zero)
    private let scrollView = ThemedScrollView(frame: .zero)
    private let filterField = ThemedSearchField(placeholder: "Filter")
    private let selectionMenuButton = NSPopUpButton(frame: .zero, pullsDown: true)

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
        table.allowsEmptySelection = true
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

    /// `project >> branch` over the session's own name — its place on top,
    /// because that is what stays put. A session's name is a summary of what it
    /// is doing this minute, and a list sorted by a title that rewrites itself
    /// under the reader is a list they cannot find anything in twice.
    private func nameCell(for session: Session) -> NSView {
        let name = ThemedLabel(
            string: session.displayName, role: .primaryText, textRole: .body)
        // From the head: the branch is the end of `project >> branch`, and it
        // is the half that tells two rows of the same project apart.
        name.lineBreakMode = .byTruncatingHead
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

        // The name, underneath, and only when it is saying something the title
        // did not — a session with no crumbs is already titled by its name.
        if session.name != session.displayName {
            let subtitle = ThemedLabel(
                string: session.name, role: .secondaryText, textRole: .caption)
            subtitle.lineBreakMode = .byTruncatingTail
            subtitle.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(subtitle)
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
