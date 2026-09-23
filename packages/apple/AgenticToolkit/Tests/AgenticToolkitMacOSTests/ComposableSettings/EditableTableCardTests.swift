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

    @Test("a field tagged past the last row is not committed")
    func outOfBoundsRowTagDoesNotCommit() throws {
        let card = makeCard()
        card.setRows(rows())
        var edited: (String, String, String)?
        card.onEdit = { edited = ($0, $1, $2) }

        // swiftlint:disable:next force_try
        let field = try! #require(
            card.tableView.view(atColumn: 1, row: 0, makeIfNecessary: true) as? NSTextField
        )
        field.tag = rows().count
        field.stringValue = "$999"
        card.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))

        #expect(edited == nil, "a row index off the end of the data must never reach onEdit")
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
