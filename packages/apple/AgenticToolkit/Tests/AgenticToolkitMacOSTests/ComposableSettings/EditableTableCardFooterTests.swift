import AppKit
import Foundation
import Testing

import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The footer's extras: buttons of the owner's own, a per-row veto on `−`,
/// and a read-only mode with no `+`/`−` at all.
@Suite("EditableTableCard footer")
@MainActor
struct EditableTableCardFooterTests {

    private typealias Card = ComposableSettings.EditableTableCard
    private typealias Row = ComposableSettings.EditableTableRow

    private func makeCard() -> Card {
        let card = Card(
            title: "Billables",
            columns: [.init(id: "day", title: "Day", width: 100)],
            emptyMessage: "None.",
            accessibilityPrefix: "test.footer"
        )
        card.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
        card.setRows([
            Row(id: "open", cells: ["day": .text("2026-09-21")]),
            Row(id: "locked", cells: ["day": .text("2026-09-20")])
        ])
        return card
    }

    @Test("a footer button is added, identified, and runs its action")
    func footerButtonRuns() {
        let card = makeCard()
        var pressed = 0

        let button = card.addFooterButton(title: "Mark Billed", identifier: "test.footer.markBilled") {
            pressed += 1
        }
        button.performClick(nil)

        #expect(button.title == "Mark Billed")
        #expect(button.accessibilityIdentifier() == "test.footer.markBilled")
        #expect(pressed == 1)
    }

    @Test("footer buttons sit after + and −, before the empty-state text")
    func footerButtonOrder() {
        let card = makeCard()
        let first = card.addFooterButton(title: "One", identifier: "one") {}
        let second = card.addFooterButton(title: "Two", identifier: "two") {}

        // swiftlint:disable:next force_try
        let stack = try! #require(card.addButton.superview as? NSStackView)
        let order = stack.arrangedSubviews
        #expect(order.firstIndex(of: card.removeButton)! < order.firstIndex(of: first)!)
        #expect(order.firstIndex(of: first)! < order.firstIndex(of: second)!)
        #expect(order.last === card.emptyLabel, "the trailing text keeps the slack at the end")
    }

    @Test("canRemoveRow vetoes − for the rows it refuses")
    func canRemoveRowVetoes() {
        let card = makeCard()
        card.canRemoveRow = { $0 != "locked" }

        card.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        #expect(card.removeButton.isEnabled)

        card.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        #expect(!card.removeButton.isEnabled, "a billed row must not look deletable")
    }

    @Test("setting canRemoveRow re-evaluates the current selection")
    func canRemoveRowAppliesAtOnce() {
        let card = makeCard()
        card.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        #expect(card.removeButton.isEnabled)

        card.canRemoveRow = { $0 != "locked" }

        #expect(!card.removeButton.isEnabled)
    }

    @Test("a read-only card hides + and −")
    func readOnlyHidesAddRemove() {
        let card = makeCard()
        card.showsAddRemove = false

        #expect(card.addButton.isHidden)
        #expect(card.removeButton.isHidden)

        card.showsAddRemove = true
        #expect(!card.addButton.isHidden)
    }
}
