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

        public let id: String
        public let title: String
        public let width: CGFloat
        public let kind: Kind
        public let isSortable: Bool

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
        case text(String)
        case toggle(Bool)
        case indicator(Bool)
        /// Greyed prompt text — a value not set yet, not a value that is empty.
        case placeholder(String)
    }

    /// One row, keyed by column id. The `id` is the caller's own — a DTO id,
    /// not a row index — because a row index stops meaning anything the moment
    /// the owner re-sorts.
    public struct EditableTableRow: Sendable, Identifiable {
        public let id: String
        public let cells: [String: EditableTableCellValue]
        /// Drawn with the warning tint: a runaway timer, an entry that needs
        /// attention. Marking is all the card does; what it means is the
        /// owner's business.
        public let isFlagged: Bool

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
    /// back**. `setRows` assigns before `reloadData`, so a
    /// `controlTextDidEndEditing` landing mid-reload reads the new rows at the
    /// old row index and commits the user's half-typed text against a record
    /// they never touched.
    ///
    /// The card owns no model. Rows arrive as values, and every interaction
    /// leaves through a closure — so the same card serves a list backed by a
    /// settings store and one backed by a daemon (`dependency-injection`).
    @MainActor
    public final class EditableTableCard: GroupView {

        // MARK: Callbacks

        public var onAdd: (() -> Void)?
        public var onRemove: ((_ rowID: String) -> Void)?
        public var onSelectionChange: ((_ rowID: String?) -> Void)?
        public var onEdit: ((_ rowID: String, _ columnID: String, _ newValue: String) -> Void)?
        public var onToggle: ((_ rowID: String, _ columnID: String, _ isOn: Bool) -> Void)?
        public var onSort: ((_ columnID: String, _ ascending: Bool) -> Void)?

        /// Asked whether the selected row may be removed; `−` is disabled when
        /// it answers false. Nil allows every row. A billed entry answers
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

        public private(set) var rows: [EditableTableRow] = []

        public var selectedRowID: String? {
            let row = tableView.selectedRow
            guard row >= 0, row < rows.count else { return nil }
            return rows[row].id
        }

        public let tableView = ThemedTableView()
        public let emptyLabel = ThemedLabel(role: .secondaryText, textRole: .body)

        public var addButton: NSButton { footer.addButton }
        public var removeButton: NSButton { footer.removeButton }

        private let columns: [EditableTableColumn]
        private let footer: AddRemoveFooterView
        private let scrollView = ThemedScrollView()
        private var isEditingField = false
        private var pendingRows: [EditableTableRow]?
        private var lastReportedSelection: String??
        private var footerActions: [ObjectIdentifier: () -> Void] = [:]

        private static let cellIdentifier = NSUserInterfaceItemIdentifier("editable-table-cell")

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
            guard !isEditingField else {
                pendingRows = rows
                return
            }
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
        func beginEditingForTests() { isEditingField = true }

        func endEditingForTests() { finishEditing() }

        private func finishEditing() {
            isEditingField = false
            if let pending = pendingRows {
                pendingRows = nil
                applyRows(pending)
            }
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
            guard let columnID = sender.identifier?.rawValue else { return }
            onToggle?(rows[row].id, columnID, sender.state == .on)
        }
    }
}

// MARK: - Data source

extension ComposableSettings.EditableTableCard: NSTableViewDataSource {

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

    public func tableView(
        _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
    ) -> NSView? {
        guard let tableColumn, row >= 0, row < rows.count else { return nil }
        let columnID = tableColumn.identifier.rawValue
        guard let column = columns.first(where: { $0.id == columnID }) else { return nil }
        let value = rows[row].cells[columnID]

        switch column.kind {
        case .toggle:
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(togglePressed(_:)))
            button.identifier = tableColumn.identifier
            button.tag = row
            if case .toggle(let isOn) = value { button.state = isOn ? .on : .off }
            button.setAccessibilityLabel(column.title)
            return button

        case .indicator:
            let label = ThemedLabel(role: .primaryText, textRole: .body)
            if case .indicator(let isOn) = value {
                label.stringValue = isOn ? "●" : "○"
                label.setAccessibilityLabel(isOn ? "\(column.title), on" : "\(column.title), off")
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
            return field
        }
    }

    private func reusableField() -> NSTextField {
        if let reused = tableView.makeView(
            withIdentifier: Self.cellIdentifier, owner: self
        ) as? NSTextField {
            return reused
        }
        let field = NSTextField(string: "")
        field.identifier = Self.cellIdentifier
        field.isBordered = false
        field.drawsBackground = false
        field.lineBreakMode = .byTruncatingTail
        field.delegate = self
        return field
    }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = ComposableSettings.EditableTableRowView(frame: .zero)
        view.isFlagged = row < rows.count && rows[row].isFlagged
        return view
    }

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

    public func controlTextDidBeginEditing(_ notification: Notification) {
        isEditingField = true
    }

    public func controlTextDidEndEditing(_ notification: Notification) {
        defer { finishEditing() }
        guard let field = notification.object as? NSTextField else { return }
        let row = field.tag
        guard row >= 0, row < rows.count else { return }
        // A reload landing mid-edit can detach the field's row view before this
        // notification arrives; `column(for:)` then answers -1.
        let columnIndex = tableView.column(for: field)
        guard columnIndex >= 0, columnIndex < columns.count else { return }
        commitEdit(rowIndex: row, columnID: columns[columnIndex].id, newValue: field.stringValue)
    }
}
