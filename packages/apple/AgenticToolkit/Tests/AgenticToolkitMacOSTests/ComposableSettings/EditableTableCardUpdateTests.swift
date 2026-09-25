import AppKit
import Foundation
import Testing

import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The card's narrow entry points: patching a few rows in place, selecting
/// a row by its record id, and a footer pull-down whose items are rebuilt
/// each time it opens.
@Suite("EditableTableCard updates")
@MainActor
struct EditableTableCardUpdateTests {

    private typealias Card = ComposableSettings.EditableTableCard
    private typealias Row = ComposableSettings.EditableTableRow

    private func makeCard() -> Card {
        let card = Card(
            title: "Runs",
            columns: [
                .init(id: "name", title: "Name", width: 200),
                .init(id: "elapsed", title: "Elapsed", width: 80)
            ],
            emptyMessage: "No runs.", accessibilityPrefix: "test.runs"
        )
        card.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
        card.layoutSubtreeIfNeeded()
        return card
    }

    private func row(_ id: String, _ elapsed: String, flagged: Bool = false) -> Row {
        Row(id: id, cells: ["name": .text(id), "elapsed": .text(elapsed)], isFlagged: flagged)
    }

    private func text(_ card: Card, row: Int, column: Int) -> String? {
        (card.tableView.view(atColumn: column, row: row, makeIfNecessary: true) as? NSTextField)?.stringValue
    }

    // MARK: - updateRows

    @Test("updateRows replaces only the named rows and keeps order and selection")
    func updateRowsPatchesInPlace() {
        let card = makeCard()
        card.setRows([row("a", "1m"), row("b", "2m"), row("c", "3m")])
        card.tableView.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)

        let complete = card.updateRows([row("b", "9m", flagged: true)])

        #expect(complete)
        #expect(card.rows.map(\.id) == ["a", "b", "c"])
        #expect(card.rows[1].isFlagged)
        #expect(text(card, row: 1, column: 1) == "9m")
        #expect(text(card, row: 0, column: 1) == "1m")
        #expect(card.selectedRowID == "c")
    }

    @Test("updateRows answers false for an id the table does not have, and ignores it")
    func updateRowsReportsUnknownIDs() {
        let card = makeCard()
        card.setRows([row("a", "1m")])

        #expect(card.updateRows([row("zz", "5m")]) == false)
        #expect(card.rows.map(\.id) == ["a"])
    }

    @Test("updateRows during an edit is held with the edit, not drawn under it")
    func updateRowsWaitsForTheEdit() {
        let card = makeCard()
        card.setRows([row("a", "1m"), row("b", "2m")])
        card.beginEditingForTests()

        card.updateRows([row("a", "7m")])
        guard case .text(let shown) = card.rows[0].cells["elapsed"] else {
            Issue.record("the elapsed cell is text"); return
        }
        #expect(shown == "1m", "the row on screen is untouched while the field is live")

        card.endEditingForTests()
        #expect(text(card, row: 0, column: 1) == "7m")
    }

    @Test("updateRows during an edit folds into a reload already held")
    func updateRowsMergesIntoTheHeldReload() {
        let card = makeCard()
        card.setRows([row("a", "1m")])
        card.beginEditingForTests()
        card.setRows([row("a", "1m"), row("b", "2m")])

        card.updateRows([row("b", "8m")])
        card.endEditingForTests()

        #expect(card.rows.map(\.id) == ["a", "b"], "the held reload is not lost")
        #expect(text(card, row: 1, column: 1) == "8m")
    }

    // MARK: - selectRow

    @Test("selectRow selects by record id and answers false for a missing one")
    func selectRowByID() {
        let card = makeCard()
        card.setRows([row("a", "1m"), row("b", "2m")])

        #expect(card.selectRow(id: "b"))
        #expect(card.selectedRowID == "b")
        #expect(card.selectRow(id: "gone") == false)
        #expect(card.selectedRowID == "b", "a missing id leaves the selection alone")
    }

    // MARK: - addFooterMenuButton

    @Test("the footer menu button is a pull-down that rebuilds its items as it opens")
    func footerMenuButtonRebuildsItems() {
        let card = makeCard()
        var names = ["One"]
        let button = card.addFooterMenuButton(title: "Assign", identifier: "test.assign") {
            names.map { NSMenuItem(title: $0, action: nil, keyEquivalent: "") }
        }

        #expect(button.pullsDown)
        // A pull-down's cell is what accessibility reads: VoiceOver hears a
        // menu button, not a push button that happens to pop a menu.
        #expect(button.cell?.accessibilityRole() == .menuButton)
        #expect(button.title == "Assign")

        names = ["One", "Two"]
        button.menu.map { $0.delegate?.menuNeedsUpdate?($0) }

        #expect(button.itemTitles == ["Assign", "One", "Two"],
                "the face is the first item, the choices follow, freshly built")
    }
}

/// A status line in a card that starts hidden must be able to come back.
@MainActor
struct ExplanationViewVisibilityTests {

    @Test("an ExplanationView hidden before it is placed reopens its row when shown")
    func hiddenExplanationReopensItsRow() {
        let group = ComposableSettings.GroupView(withTitle: "History")
        let notice = ComposableSettings.ExplanationView(withText: "")
        notice.isHidden = true
        group.addSettingSubview(notice, style: .continuation)
        #expect(notice.superview?.isHidden == true)

        notice.text = "Deriving history for 2 sessions."
        notice.isHidden = false

        #expect(notice.superview?.isHidden == false,
                "the card row copied isHidden at placement; it must follow the view back")
        #expect(notice.text == "Deriving history for 2 sessions.")
    }
}

/// A view model's `explanation` is drawn: a secondary line tucked under the
/// control it explains, which comes and goes with that control.
@MainActor
struct GroupViewExplanationTests {

    private func explanations(in group: ComposableSettings.GroupView) -> [ComposableSettings.ExplanationView] {
        func walk(_ view: NSView) -> [ComposableSettings.ExplanationView] {
            view.subviews.flatMap { sub -> [ComposableSettings.ExplanationView] in
                if let found = sub as? ComposableSettings.ExplanationView { return [found] }
                return walk(sub)
            }
        }
        return walk(group)
    }

    @Test("a setting's explanation is added as a line under it")
    func explanationIsDrawnUnderItsSetting() {
        let group = ComposableSettings.GroupView(withTitle: "Billing")
        let checkbox = ComposableSettings.CheckboxView(with: ComposableSettings.ViewModel<Bool>(
            title: "Round up", get: { false }, set: { _ in }, explanation: "Applies to new projects only."))

        group.addSettingSubview(checkbox)

        let lines = explanations(in: group)
        #expect(lines.map(\.text) == ["Applies to new projects only."])
        #expect(lines.first?.isHidden == false)
        #expect(lines.first?.superview?.isHidden == false)
    }

    @Test("a setting without an explanation adds no line")
    func noExplanationNoLine() {
        let group = ComposableSettings.GroupView(withTitle: "Billing")
        group.addSettingSubview(ComposableSettings.CheckboxView(with: ComposableSettings.ViewModel<Bool>(
            title: "Round up", get: { false }, set: { _ in })))
        group.addSettingSubview(ComposableSettings.CheckboxView(with: ComposableSettings.ViewModel<Bool>(
            title: "Blank", get: { false }, set: { _ in }, explanation: "  \n")))

        #expect(explanations(in: group).isEmpty)
    }

    @Test("the explanation of a conditional setting hides and reopens with it")
    func explanationFollowsAConditionalSetting() async throws {
        let setting = UserSetting<Bool>("agentic_toolkit_group_explanation_test", default: false)
        setting.value = false
        defer { setting.value = false }
        let checkbox = ComposableSettings.CheckboxView(with: ComposableSettings.ViewModel<Bool>(
            title: "Round up", get: { false }, set: { _ in }, explanation: "Shown only when enabled."))
        let conditional = ComposableSettings.ConditionalView(observing: setting, child: checkbox) { $0 }
        let group = ComposableSettings.GroupView(withTitle: "Billing")

        group.addSettingSubview(conditional)
        let line = try #require(explanations(in: group).first)
        #expect(line.text == "Shown only when enabled.")
        #expect(line.isHidden == true)
        #expect(line.superview?.isHidden == true)

        setting.value = true
        for _ in 0..<100 where line.isHidden {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(line.isHidden == false)
        #expect(line.superview?.isHidden == false)

        setting.value = false
        for _ in 0..<100 where !line.isHidden {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(line.isHidden == true)
        #expect(line.superview?.isHidden == true)
    }
}
