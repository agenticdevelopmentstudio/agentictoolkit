import AppKit

import AgenticToolkitCore
import AgenticToolkitCoreMacOS

extension ComposableSettings {

    /// One column of an ``EditableTableCard``.
    public struct EditableTableColumn: Sendable {

        /// What the column's cells are made of.
        public enum Kind: Sendable {
            /// Text, optionally typed into in place.
            case text(editable: Bool)
            /// A switch, reported through `onToggle`.
            case toggle
            /// A filled or hollow dot — a running timer, a connected server.
            case indicator
        }

        /// The caller's key for the column; what every callback reports.
        public let id: String
        /// The header text.
        public let title: String
        /// The column's initial width in points.
        public let width: CGFloat
        /// What the column's cells are made of.
        public let kind: Kind
        /// Whether clicking the header reports a sort through `onSort`.
        public let isSortable: Bool

        /// A column; text columns are read-only unless `kind` says otherwise.
        public init(
            id: String, title: String, width: CGFloat,
            kind: Kind = .text(editable: false), isSortable: Bool = false
        ) {
            self.id = id
            self.title = title
            self.width = width
            self.kind = kind
            self.isSortable = isSortable
        }
    }

    /// What one cell shows. A cell whose column expects text but which carries
    /// a toggle simply draws nothing: the card reports the mismatch to no one,
    /// because a table that refuses to draw is worse than one with a gap.
    public enum EditableTableCellValue: Sendable {
        /// Plain text.
        case text(String)
        /// A switch, on or off.
        case toggle(Bool)
        /// A dot, filled when true.
        case indicator(Bool)
        /// Greyed prompt text — a value not set yet, not a value that is empty.
        case placeholder(String)
    }

    /// One row, keyed by column id. The `id` is the caller's own — a DTO id,
    /// not a row index — because a row index stops meaning anything the moment
    /// the owner re-sorts.
    public struct EditableTableRow: Sendable, Identifiable {
        /// The caller's own id for the record this row shows.
        public let id: String
        /// The row's values, keyed by column id. A missing key draws an empty cell.
        public let cells: [String: EditableTableCellValue]
        /// Drawn with the warning tint: a runaway timer, an entry that needs
        /// attention. Marking is all the card does; what it means is the
        /// owner's business.
        public let isFlagged: Bool

        /// A row for the record `id`.
        public init(id: String, cells: [String: EditableTableCellValue], isFlagged: Bool = false) {
            self.id = id
            self.cells = cells
            self.isFlagged = isFlagged
        }
    }

    /// A row view that can call itself out.
    ///
    /// The tint goes over the *background*, not the selection: a flagged row
    /// that is also selected must still read as selected, and painting over
    /// `drawSelection` would take that away exactly when the user is looking
    /// at it. `palette` is the base class's, so the wash follows a live theme
    /// change with the rest of the row.
    public final class EditableTableRowView: ThemedTableRowView {
        /// Whether the row draws the warning wash.
        public var isFlagged = false {
            didSet { needsDisplay = true }
        }

        public override func drawBackground(in dirtyRect: NSRect) {
            super.drawBackground(in: dirtyRect)
            guard isFlagged else { return }
            palette.nsColor(.warning).withAlphaComponent(0.18).setFill()
            dirtyRect.fill(using: .sourceOver)
        }
    }

    /// A settings card whose single row is a table: sortable headers, cells
    /// edited in place, and a `+`/`−` footer.
    ///
    /// `GitGlobalConfigTableView` is this view welded to git config, and every
    /// non-git line of it is here instead — including the one that is not
    /// obvious: a reload arriving while a cell is being edited is **held
    /// back** (`EditDeferredValue`, shared with that table).
    ///
    /// Holding back is not enough on its own, because it only starts at the
    /// first keystroke: a field that has focus but no typing yet is ended by
    /// the reload itself, after `rows` has already been replaced. So every
    /// text cell also carries the row id, column id and text it was filled
    /// with, and an edit is committed against *those* — never against a row
    /// index or a column position, both of which a reload or a header drag
    /// can change under the field — and not at all when the text is unchanged.
    ///
    /// The card owns no model. Rows arrive as values, and every interaction
    /// leaves through a closure — so the same card serves a list backed by a
    /// settings store and one backed by a daemon (`dependency-injection`).
    @MainActor
    public final class EditableTableCard: GroupView {

        // MARK: Callbacks

        /// `+` was clicked.
        public var onAdd: (() -> Void)?
        /// `−` was clicked with this row selected.
        public var onRemove: ((_ rowID: String) -> Void)?
        /// The user selected a row, or cleared the selection (nil).
        public var onSelectionChange: ((_ rowID: String?) -> Void)?
        /// A text cell's edit ended with text different from what it was filled with.
        public var onEdit: ((_ rowID: String, _ columnID: String, _ newValue: String) -> Void)?
        /// A toggle cell was flipped.
        public var onToggle: ((_ rowID: String, _ columnID: String, _ isOn: Bool) -> Void)?
        /// A sortable header was clicked. The card does not sort; the owner re-sorts and calls `setRows`.
        public var onSort: ((_ columnID: String, _ ascending: Bool) -> Void)?

        /// Asked whether the selected row may be removed; `−` is disabled when
        /// it answers false. Nil allows every row. A locked record answers
        /// false: a button that looks live and then refuses teaches nothing.
        public var canRemoveRow: ((_ rowID: String) -> Bool)? {
            didSet { updateButtons() }
        }

        /// False hides `+` and `−`, for a table that only reports (a history,
        /// a log). Buttons added with `addFooterButton` stay.
        public var showsAddRemove = true {
            didSet {
                footer.addButton.isHidden = !showsAddRemove
                footer.removeButton.isHidden = !showsAddRemove
            }
        }

        // MARK: State

        /// The rows on screen — the last `setRows` that was not held back by an edit.
        public private(set) var rows: [EditableTableRow] = []

        /// The id of the selected row, or nil.
        public var selectedRowID: String? {
            let row = tableView.selectedRow
            guard row >= 0, row < rows.count else { return nil }
            return rows[row].id
        }

        /// The table itself, for layout, tests and accessibility.
        public let tableView = ThemedTableView()
        /// Shown over the table while it has no rows.
        public let emptyLabel = ThemedLabel(role: .secondaryText, textRole: .body)

        /// The footer's `+` button.
        public var addButton: NSButton { footer.addButton }
        /// The footer's `−` button.
        public var removeButton: NSButton { footer.removeButton }

        private let columns: [EditableTableColumn]
        private let footer: AddRemoveFooterView
        private let scrollView = ThemedScrollView()
        private var heldRows = EditDeferredValue<[EditableTableRow]>()
        private var lastReportedSelection: String??
        private var footerActions: [ObjectIdentifier: () -> Void] = [:]
        private weak var observedWindow: NSWindow?

        private static let cellIdentifier = NSUserInterfaceItemIdentifier("editable-table-cell")
        private static let toggleIdentifier = NSUserInterfaceItemIdentifier("editable-table-toggle")
        private static let indicatorIdentifier = NSUserInterfaceItemIdentifier("editable-table-indicator")
        private static let rowViewIdentifier = NSUserInterfaceItemIdentifier("editable-table-row")

        /// - Parameters:
        ///   - visibleRows: how many rows the table shows before scrolling. A
        ///     table that grows with its content would make the card jump every
        ///     time a row was added.
        ///   - accessibilityPrefix: identifiers for the table and its two
        ///     buttons are derived from it, so a UI test can address them.
        public init(
            title: String,
            columns: [EditableTableColumn],
            emptyMessage: String,
            visibleRows: Int = 6,
            accessibilityPrefix: String
        ) {
            self.columns = columns
            self.footer = AddRemoveFooterView(accessibilityPrefix: accessibilityPrefix)
            super.init(withHeaderView: HeaderView(title: title))
            emptyLabel.stringValue = emptyMessage
            footer.onAdd = { [weak self] in self?.onAdd?() }
            footer.onRemove = { [weak self] in
                guard let self, let id = self.selectedRowID else { return }
                self.onRemove?(id)
            }
            footer.trailingView = emptyLabel
            setUpTable(visibleRows: visibleRows, accessibilityPrefix: accessibilityPrefix)
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { nil }

        // MARK: - Content

        /// Replaces the rows — unless a cell is being edited, in which case the
        /// replacement waits for that edit to commit.
        public func setRows(_ rows: [EditableTableRow]) {
            guard let rows = heldRows.offer(rows) else { return }
            applyRows(rows)
        }

        private func applyRows(_ rows: [EditableTableRow]) {
            let previous = selectedRowID
            self.rows = rows
            tableView.reloadData()
            // A selection is a row id, not a row number: restore it by id, and
            // let it go if that row is gone. Keeping the index would leave the
            // remove button aimed at whatever slid into that slot.
            if let previous, let index = rows.firstIndex(where: { $0.id == previous }) {
                tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            } else if previous != nil {
                tableView.deselectAll(nil)
            }
            emptyLabel.isHidden = !rows.isEmpty
            tableView.headerView?.isHidden = rows.isEmpty
            updateButtons()
        }

        /// Applies one edited cell. Public so the owner can drive it in a test
        /// without an NSTextField and a live field editor.
        public func commitEdit(rowIndex: Int, columnID: String, newValue: String) {
            guard rowIndex >= 0, rowIndex < rows.count else { return }
            onEdit?(rows[rowIndex].id, columnID, newValue)
        }

        /// Applies one edited cell to the row with `rowID`. A row that is no
        /// longer in the table is ignored: the text was typed into a record
        /// that has since gone, and no other row may receive it.
        public func commitEdit(rowID: String, columnID: String, newValue: String) {
            guard rows.contains(where: { $0.id == rowID }) else { return }
            onEdit?(rowID, columnID, newValue)
        }

        /// A push button in the footer, after `+`/`−`. The owner decides when
        /// it is enabled. The card only places it and reports the click.
        @discardableResult
        public func addFooterButton(
            title: String, identifier: String, action: @escaping () -> Void
        ) -> NSButton {
            let button = NSButton(title: title, target: self, action: #selector(footerButtonPressed(_:)))
            button.bezelStyle = .push
            button.controlSize = .small
            _ = button.accessibilityID(identifier)
            footerActions[ObjectIdentifier(button)] = action
            footer.addAccessoryView(button)
            return button
        }

        @objc private func footerButtonPressed(_ sender: NSButton) {
            footerActions[ObjectIdentifier(sender)]?()
        }

        // MARK: - Test seams

        /// The two halves of "a field is being edited", without a field editor.
        /// Hosting a real one in a test means a window, a first responder and a
        /// run loop — three things that make a test flaky for no extra coverage.
        func beginEditingForTests() { heldRows.beginEditing() }

        func endEditingForTests() { finishEditing() }

        private func finishEditing() {
            if let pending = heldRows.endEditing() {
                applyRows(pending)
            }
        }

        // MARK: - Window lifetime

        /// AppKit sends no end-of-editing notification when a window is closed
        /// with a field editor still live, and a reused window keeps that
        /// editor as first responder. Without this, every later `setRows`
        /// would be held for an edit that already ended, and the reopened
        /// table would show stale rows.
        public override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if let observedWindow {
                NotificationCenter.default.removeObserver(
                    self, name: NSWindow.willCloseNotification, object: observedWindow)
            }
            observedWindow = newWindow
            if let newWindow {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(windowWillClose(_:)),
                    name: NSWindow.willCloseNotification, object: newWindow)
            }
        }

        @objc private func windowWillClose(_ notification: Notification) {
            // End the edit the way a click elsewhere would: the text commits to
            // the row it was typed into (see `CellField`) and the held reload
            // lands. `finishEditing` covers a window whose responder was not
            // one of this table's fields.
            if let window = notification.object as? NSWindow,
               let editor = window.firstResponder as? NSText,
               let field = editor.delegate as? NSView,
               field.isDescendant(of: tableView) {
                window.makeFirstResponder(nil)
            }
            finishEditing()
        }

        // MARK: - Setup

        private func setUpTable(visibleRows: Int, accessibilityPrefix: String) {
            for column in columns {
                let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.id))
                tableColumn.title = column.title
                tableColumn.width = column.width
                if column.isSortable {
                    tableColumn.sortDescriptorPrototype =
                        NSSortDescriptor(key: column.id, ascending: true)
                }
                tableView.addTableColumn(tableColumn)
            }
            tableView.dataSource = self
            tableView.delegate = self
            tableView.usesAlternatingRowBackgroundColors = false
            tableView.allowsMultipleSelection = false
            tableView.accessibilityID("\(accessibilityPrefix).table")

            scrollView.documentView = tableView
            scrollView.hasVerticalScroller = true
            scrollView.translatesAutoresizingMaskIntoConstraints = false

            emptyLabel.isHidden = false

            let stack = NSStackView(views: [scrollView, footer])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 6
            stack.translatesAutoresizingMaskIntoConstraints = false

            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: container.topAnchor),
                stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
                scrollView.heightAnchor.constraint(
                    equalToConstant: CGFloat(visibleRows) * (tableView.rowHeight + 2) + 24)
            ])
            addSettingSubview(container)
            updateButtons()
        }

        private func updateButtons() {
            guard let selected = selectedRowID else {
                footer.isRemoveEnabled = false
                return
            }
            footer.isRemoveEnabled = canRemoveRow?(selected) ?? true
        }

        @objc fileprivate func togglePressed(_ sender: NSButton) {
            let row = sender.tag
            guard row >= 0, row < rows.count else { return }
            guard let columnID = (sender as? EditableTableToggle)?.toggleColumnID else { return }
            onToggle?(rows[row].id, columnID, sender.state == .on)
        }
    }
}

// MARK: - Data source

extension ComposableSettings.EditableTableCard: NSTableViewDataSource {

    /// `NSTableViewDataSource`: one table row per `rows` element.
    public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    /// The card reports the click and sorts nothing: the owner holds the model,
    /// so it holds the order.
    public func tableView(
        _ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
    ) {
        guard let descriptor = tableView.sortDescriptors.first, let key = descriptor.key else {
            return
        }
        onSort?(key, descriptor.ascending)
    }
}

// MARK: - Delegate

extension ComposableSettings.EditableTableCard: NSTableViewDelegate {

    /// `NSTableViewDelegate`: a recycled cell for the column's kind, filled from the row.
    public func tableView(
        _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
    ) -> NSView? {
        guard let tableColumn, row >= 0, row < rows.count else { return nil }
        let columnID = tableColumn.identifier.rawValue
        guard let column = columns.first(where: { $0.id == columnID }) else { return nil }
        let value = rows[row].cells[columnID]

        // Every kind is dequeued by identifier, so scrolling a long table
        // recycles cells instead of building (and theming) one per row.
        switch column.kind {
        case .toggle:
            let button = reusableToggle()
            // The button's own `identifier` is the reuse identifier, so the
            // column id is carried in `toggleColumnID`.
            button.toggleColumnID = columnID
            button.tag = row
            if case .toggle(let isOn) = value {
                button.state = isOn ? .on : .off
            } else {
                button.state = .off
            }
            button.setAccessibilityLabel(column.title)
            return button

        case .indicator:
            let label = reusableIndicator()
            if case .indicator(let isOn) = value {
                label.stringValue = isOn ? "●" : "○"
                label.setAccessibilityLabel(isOn ? "\(column.title), on" : "\(column.title), off")
            } else {
                label.stringValue = ""
                label.setAccessibilityLabel(nil)
            }
            return label

        case .text(let editable):
            let field = reusableField()
            field.isEditable = editable
            field.tag = row
            switch value {
            case .text(let text):
                field.stringValue = text
                field.placeholderString = nil
            case .placeholder(let prompt):
                field.stringValue = ""
                field.placeholderString = prompt
            default:
                field.stringValue = ""
                field.placeholderString = nil
            }
            field.bind(rowID: rows[row].id, columnID: columnID, shownText: field.stringValue)
            return field
        }
    }

    private func reusableField() -> ComposableSettings.EditableTableCellField {
        if let reused = tableView.makeView(
            withIdentifier: Self.cellIdentifier, owner: self
        ) as? ComposableSettings.EditableTableCellField {
            return reused
        }
        let field = ComposableSettings.EditableTableCellField(string: "")
        field.identifier = Self.cellIdentifier
        field.isBordered = false
        field.drawsBackground = false
        field.lineBreakMode = .byTruncatingTail
        field.delegate = self
        return field
    }

    private func reusableToggle() -> ComposableSettings.EditableTableToggle {
        if let reused = tableView.makeView(
            withIdentifier: Self.toggleIdentifier, owner: self
        ) as? ComposableSettings.EditableTableToggle {
            return reused
        }
        let button = ComposableSettings.EditableTableToggle(
            checkboxWithTitle: "", target: self, action: #selector(togglePressed(_:)))
        button.identifier = Self.toggleIdentifier
        return button
    }

    private func reusableIndicator() -> ThemedLabel {
        if let reused = tableView.makeView(
            withIdentifier: Self.indicatorIdentifier, owner: self
        ) as? ThemedLabel {
            return reused
        }
        let label = ThemedLabel(role: .primaryText, textRole: .body)
        label.identifier = Self.indicatorIdentifier
        return label
    }

    /// `NSTableViewDelegate`: a recycled `EditableTableRowView`, flagged per row.
    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = tableView.makeView(
            withIdentifier: Self.rowViewIdentifier, owner: self
        ) as? ComposableSettings.EditableTableRowView ?? {
            let fresh = ComposableSettings.EditableTableRowView(frame: .zero)
            fresh.identifier = Self.rowViewIdentifier
            return fresh
        }()
        view.isFlagged = row < rows.count && rows[row].isFlagged
        return view
    }

    /// `NSTableViewDelegate`: reports the selection and re-asks `canRemoveRow`.
    public func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
        let current = selectedRowID
        // `reloadData` re-announces the same selection; reporting it again would
        // have the owner reload its detail pane on every unrelated refresh.
        guard lastReportedSelection != .some(current) else { return }
        lastReportedSelection = .some(current)
        onSelectionChange?(current)
    }
}

// MARK: - Editing

extension ComposableSettings.EditableTableCard: NSTextFieldDelegate {

    /// `NSTextFieldDelegate`: from the first keystroke, reloads are held back.
    public func controlTextDidBeginEditing(_ notification: Notification) {
        heldRows.beginEditing()
    }

    /// Commits against the row and column the field was *filled for*, not
    /// against `field.tag` or `tableView.column(for:)`: by the time this runs
    /// a reload may have replaced `rows` (so the tag names another record),
    /// and a header drag may have moved the column (so its display position
    /// names another column). Text the user did not change is not committed
    /// at all — focus alone is not an edit.
    public func controlTextDidEndEditing(_ notification: Notification) {
        defer { finishEditing() }
        guard let field = notification.object as? ComposableSettings.EditableTableCellField,
              let binding = field.binding,
              field.stringValue != binding.shownText
        else { return }
        commitEdit(rowID: binding.rowID, columnID: binding.columnID, newValue: field.stringValue)
    }
}

// MARK: - Cells

extension ComposableSettings {

    /// A text cell that remembers which record and column it was filled for,
    /// and with what text. See `EditableTableCard.controlTextDidEndEditing`.
    public final class EditableTableCellField: NSTextField {

        /// What the cell was last filled with by the table.
        public struct Binding: Equatable, Sendable {
            /// The id of the row the cell was filled for.
            public let rowID: String
            /// The id of the column the cell sits in.
            public let columnID: String
            /// The text the table put in the cell; an edit ending on the same text is not reported.
            public let shownText: String
        }

        /// What the cell was last filled with; nil until the table fills it.
        public private(set) var binding: Binding?

        func bind(rowID: String, columnID: String, shownText: String) {
            binding = Binding(rowID: rowID, columnID: columnID, shownText: shownText)
        }
    }

    /// A toggle cell. Its `identifier` is the reuse identifier, so the column
    /// it reports for is carried separately.
    public final class EditableTableToggle: NSButton {
        /// The id of the column this toggle was last filled for.
        public var toggleColumnID: String?
    }
}
