import AppKit
import Foundation
import Testing

import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The table three billing windows are built from.
@Suite("EditableTableCard")
@MainActor
struct EditableTableCardTests {

    private typealias Card = ComposableSettings.EditableTableCard
    private typealias Column = ComposableSettings.EditableTableColumn
    private typealias Row = ComposableSettings.EditableTableRow

    private static let columns = [
        Column(id: "path", title: "Path", width: 200, kind: .text(editable: true), isSortable: true),
        Column(id: "rate", title: "Rate", width: 80, kind: .text(editable: true)),
        Column(id: "on", title: "Billing", width: 60, kind: .toggle)
    ]

    private func makeCard() -> Card {
        let card = Card(
            title: "Repos", columns: Self.columns,
            emptyMessage: "No repos yet.", accessibilityPrefix: "billing.repos"
        )
        card.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
        card.layoutSubtreeIfNeeded()
        return card
    }

    private func rows() -> [Row] {
        [
            Row(id: "r1", cells: ["path": .text("/src/app"), "rate": .text("$120"), "on": .toggle(true)]),
            Row(id: "r2", cells: ["path": .text("/src/lib"), "rate": .text("$90"), "on": .toggle(false)])
        ]
    }

    // MARK: - Columns

    @Test("declared columns become table columns, in order")
    func columnsAreBuilt() {
        let card = makeCard()

        #expect(card.tableView.tableColumns.map(\.identifier.rawValue) == ["path", "rate", "on"])
        #expect(card.tableView.tableColumns[0].title == "Path")
    }

    @Test("only a sortable column carries a sort descriptor")
    func onlySortableColumnsSort() {
        let card = makeCard()

        #expect(card.tableView.tableColumns[0].sortDescriptorPrototype != nil)
        #expect(card.tableView.tableColumns[1].sortDescriptorPrototype == nil,
                "a header that cannot sort must not look like it can")
    }

    @Test("clicking a sortable header reports the click instead of reordering")
    func sortIsReportedNotPerformed() {
        let card = makeCard()
        card.setRows(rows())
        var sorted: (String, Bool)?
        card.onSort = { sorted = ($0, $1) }

        card.tableView.sortDescriptors = [NSSortDescriptor(key: "path", ascending: true)]

        #expect(sorted?.0 == "path")
        #expect(sorted?.1 == true)
        #expect(card.rows.map(\.id) == ["r1", "r2"], "the card holds the order it was given")
    }

    // MARK: - Rows

    @Test("rows are shown, one table row each")
    func rowsAreShown() {
        let card = makeCard()
        card.setRows(rows())

        #expect(card.tableView.numberOfRows == 2)
        let cell = card.tableView.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTextField
        #expect(cell?.stringValue == "/src/app")
    }

    @Test("an empty table says so, and hides its header")
    func emptyStateIsASentence() {
        let card = makeCard()
        card.setRows([])

        #expect(card.emptyLabel.isHidden == false)
        #expect(card.emptyLabel.stringValue == "No repos yet.")

        card.setRows(rows())
        #expect(card.emptyLabel.isHidden, "the message is for an empty table only")
    }

    @Test("a toggle cell is a switch, and reports its new state")
    func toggleCellsReport() {
        let card = makeCard()
        card.setRows(rows())
        var toggled: (String, String, Bool)?
        card.onToggle = { toggled = ($0, $1, $2) }

        // swiftlint:disable:next force_try
        let button = try! #require(
            card.tableView.view(atColumn: 2, row: 1, makeIfNecessary: true) as? NSButton
        )
        #expect(button.state == .off)
        // `performClick` drives AppKit's own click machinery, which flips
        // whatever `.state` currently holds; pre-setting `.on` here would just
        // flip it straight back to `.off` before the action fires. A single
        // click from the real, off starting state is what turns it on.
        button.performClick(nil)

        #expect(toggled?.0 == "r2")
        #expect(toggled?.1 == "on")
        #expect(toggled?.2 == true)
    }

    @Test("a committed cell edit reports the row, column and new text")
    func editsReport() {
        let card = makeCard()
        card.setRows(rows())
        var edited: (String, String, String)?
        card.onEdit = { edited = ($0, $1, $2) }

        card.commitEdit(rowIndex: 0, columnID: "rate", newValue: "$150")

        #expect(edited?.0 == "r1")
        #expect(edited?.1 == "rate")
        #expect(edited?.2 == "$150")
    }

    @Test("a reload arriving mid-edit is held until the edit commits")
    func reloadWaitsForAnInFlightEdit() {
        let card = makeCard()
        card.setRows(rows())
        card.beginEditingForTests()

        card.setRows([Row(id: "r9", cells: ["path": .text("/src/new")])])
        #expect(card.rows.map(\.id) == ["r1", "r2"],
                "replacing rows under a live field commits the user's text against another row")

        card.endEditingForTests()
        #expect(card.rows.map(\.id) == ["r9"])
    }

    // MARK: - Real editing delegate

    /// `commitEdit` above is the seam a test drives directly. These exercise
    /// the actual `NSTextFieldDelegate` callback AppKit calls when a live
    /// field editor resigns, tag/column lookup and all.
    @Test("ending a real field's edit reports through the delegate, not just the test seam")
    func realFieldEditReportsThroughDelegate() throws {
        let card = makeCard()
        card.setRows(rows())
        var edited: (String, String, String)?
        card.onEdit = { edited = ($0, $1, $2) }

        // swiftlint:disable:next force_try
        let field = try! #require(
            card.tableView.view(atColumn: 1, row: 0, makeIfNecessary: true) as? NSTextField
        )
        field.stringValue = "$150"
        card.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))

        #expect(edited?.0 == "r1")
        #expect(edited?.1 == "rate")
        #expect(edited?.2 == "$150")
    }

    @Test("a field whose row is gone is not committed")
    func goneRowDoesNotCommit() throws {
        let card = makeCard()
        card.setRows(rows())
        var edited: (String, String, String)?
        card.onEdit = { edited = ($0, $1, $2) }

        // swiftlint:disable:next force_try
        let field = try! #require(
            card.tableView.view(atColumn: 1, row: 1, makeIfNecessary: true) as? NSTextField
        )
        // The reload removes r2 while its field is live (no keystroke yet, so
        // nothing held it back).
        card.setRows([rows()[0]])
        field.stringValue = "$999"
        card.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))

        #expect(edited == nil, "text typed into a deleted record must never reach another row")
    }

    // MARK: - Review V8-a: a reload during a focused edit

    /// Newest-first rows: a new record arrives at the top and every existing
    /// row slides down one index.
    private func datedRows(_ ids: [String]) -> [Row] {
        ids.map { Row(id: $0, cells: ["path": .text("/\($0)"), "rate": .text("rate-\($0)")]) }
    }

    @Test("focus without typing, then a reload: nothing is committed to any row")
    func focusedUnchangedFieldIsNotCommittedAfterReload() throws {
        let card = makeCard()
        card.setRows(datedRows(["sep23", "sep22", "sep21"]))
        var edits: [(String, String, String)] = []
        card.onEdit = { edits.append(($0, $1, $2)) }

        let window = host(card)
        card.tableView.displayIfNeeded()
        // swiftlint:disable:next force_try
        let field = try! #require(
            card.tableView.view(atColumn: 1, row: 2, makeIfNecessary: false) as? NSTextField
        )
        // A real field editor, focused but with no keystroke: the reload is
        // not held, replaces the rows, and `reloadData` ends the edit itself.
        #expect(window.makeFirstResponder(field))
        #expect(field.currentEditor() != nil)
        card.setRows(datedRows(["sep24", "sep23", "sep22", "sep21"]))
        window.makeFirstResponder(nil)

        #expect(edits.isEmpty,
                "unchanged text is not an edit; committing it reprices another row: \(edits)")
    }

    private func host(_ card: Card) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(card)
        card.layoutSubtreeIfNeeded()
        return window
    }

    @Test("text typed before a reload commits to the row it was typed into")
    func typedTextFollowsItsRowAcrossAReload() throws {
        let card = makeCard()
        card.setRows(datedRows(["sep23", "sep22", "sep21"]))
        var edits: [(String, String, String)] = []
        card.onEdit = { edits.append(($0, $1, $2)) }

        // swiftlint:disable:next force_try
        let field = try! #require(
            card.tableView.view(atColumn: 1, row: 2, makeIfNecessary: true) as? NSTextField
        )
        field.stringValue = "1.5"
        card.setRows(datedRows(["sep24", "sep23", "sep22", "sep21"]))
        card.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))

        #expect(edits.count == 1)
        #expect(edits.first?.0 == "sep21", "row index 2 is sep22 now; the text belongs to sep21")
        #expect(edits.first?.1 == "rate")
    }

    // MARK: - Review V8-b: reordered columns

    @Test("an edit after a header drag is saved under the column it was typed into")
    func reorderedColumnCommitsUnderItsOwnID() throws {
        let card = makeCard()
        card.setRows(rows())
        var edited: (String, String, String)?
        card.onEdit = { edited = ($0, $1, $2) }

        // Drag Rate left of Path: display order is now rate, path, on.
        card.tableView.moveColumn(1, toColumn: 0)
        #expect(card.tableView.tableColumns.map(\.identifier.rawValue) == ["rate", "path", "on"])

        // swiftlint:disable:next force_try
        let field = try! #require(
            card.tableView.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTextField
        )
        field.stringValue = "$150"
        card.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))

        #expect(edited?.0 == "r1")
        #expect(edited?.1 == "rate", "display position 0 is Rate now, not Path")
    }

    // MARK: - Review V24-b: window closed mid-edit

    @Test("closing the window mid-edit releases the held reload")
    func closingTheWindowReleasesHeldRows() {
        let card = makeCard()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(card)
        card.setRows(rows())
        card.beginEditingForTests()
        card.setRows([Row(id: "r9", cells: ["path": .text("/src/new")])])
        #expect(card.rows.map(\.id) == ["r1", "r2"])

        window.close()

        #expect(card.rows.map(\.id) == ["r9"],
                "a reused window would otherwise park every later reload forever")
        card.setRows(rows())
        #expect(card.rows.map(\.id) == ["r1", "r2"], "nothing is held after the close")
    }

    // MARK: - Review V17-e: recycling

    @Test("row views and indicator cells are recycled while scrolling")
    func rowViewsAreRecycled() throws {
        let columns = [
            Column(id: "on", title: "Live", width: 40, kind: .indicator),
            Column(id: "path", title: "Path", width: 200, kind: .text(editable: false))
        ]
        let card = Card(title: "Many", columns: columns, emptyMessage: "", visibleRows: 5,
                        accessibilityPrefix: "many")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        card.frame = NSRect(x: 0, y: 0, width: 480, height: 400)
        window.contentView?.addSubview(card)
        card.setRows((0..<300).map {
            Row(id: "r\($0)", cells: ["on": .indicator($0 % 2 == 0), "path": .text("/\($0)")])
        })
        card.layoutSubtreeIfNeeded()
        card.tableView.displayIfNeeded()

        // Held strongly, so a freed view's address cannot be handed to a new one
        // and pass for recycling.
        var seenRows: [NSTableRowView] = []
        var seenIndicators: [NSView] = []
        func collect() {
            card.tableView.enumerateAvailableRowViews { rowView, _ in
                seenRows.append(rowView)
                if let cell = rowView.view(atColumn: 0) as? NSView { seenIndicators.append(cell) }
            }
        }
        collect()
        for target in stride(from: 20, through: 280, by: 20) {
            card.tableView.scrollRowToVisible(target)
            card.layoutSubtreeIfNeeded()
            card.tableView.displayIfNeeded()
            collect()
        }

        let distinctRows = Set(seenRows.map(ObjectIdentifier.init))
        let distinctIndicators = Set(seenIndicators.map(ObjectIdentifier.init))
        #expect(distinctRows.count < seenRows.count / 2,
                "each scrolled-in row built a fresh row view: \(distinctRows.count) of \(seenRows.count)")
        #expect(distinctIndicators.count < seenIndicators.count / 2,
                "each scrolled-in row built a fresh indicator: \(distinctIndicators.count) of \(seenIndicators.count)")
    }

    @Test("a field the table doesn't know about is not committed")
    func fieldNotInTableDoesNotCommit() {
        let card = makeCard()
        card.setRows(rows())
        var edited: (String, String, String)?
        card.onEdit = { edited = ($0, $1, $2) }

        // A standalone field, never handed out by the table: `column(for:)`
        // answers -1 for it, the same as a field whose row view was detached
        // by a reload landing between the field editor's begin and end.
        let orphanField = NSTextField(string: "$1")
        orphanField.tag = 0
        card.controlTextDidEndEditing(
            Notification(name: NSControl.textDidEndEditingNotification, object: orphanField)
        )

        #expect(edited == nil, "a field the table can't place a column for must never reach onEdit")
    }

    // MARK: - Footer

    @Test("add is always live; remove follows the selection")
    func footerButtonsFollowSelection() {
        let card = makeCard()
        card.setRows(rows())
        var added = 0
        var removed: String?
        card.onAdd = { added += 1 }
        card.onRemove = { removed = $0 }

        #expect(card.addButton.isEnabled)
        #expect(!card.removeButton.isEnabled, "nothing is selected, so nothing can be removed")

        card.addButton.performClick(nil)
        #expect(added == 1)

        card.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        #expect(card.removeButton.isEnabled)
        #expect(card.selectedRowID == "r2")

        card.removeButton.performClick(nil)
        #expect(removed == "r2")
    }

    @Test("selection changes are reported, including losing it")
    func selectionIsReported() {
        let card = makeCard()
        card.setRows(rows())
        var seen: [String?] = []
        card.onSelectionChange = { seen.append($0) }

        card.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        card.tableView.deselectAll(nil)

        #expect(seen == ["r1", nil])
    }

    @Test("a selected row that goes away takes the selection with it")
    func selectionDoesNotSurviveItsRow() {
        let card = makeCard()
        card.setRows(rows())
        card.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)

        card.setRows([rows()[0]])

        #expect(card.selectedRowID == nil)
        #expect(!card.removeButton.isEnabled,
                "a live remove button pointing at a deleted row deletes the wrong thing")
    }

    @Test("a flagged row is marked, so a runaway timer is visible at a glance")
    func flaggedRowsAreMarked() {
        let card = makeCard()
        card.setRows([Row(id: "r1", cells: ["path": .text("/src/app")], isFlagged: true)])

        let rowView = card.tableView.rowView(atRow: 0, makeIfNecessary: true)
        #expect((rowView as? ComposableSettings.EditableTableRowView)?.isFlagged == true)
    }
}
