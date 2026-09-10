import AgenticToolkitCore
import AppKit
import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class GitGlobalConfigTableViewTests: XCTestCase {
    func testSetEntriesPopulatesRows() {
        let view = GitGlobalConfigTableView()
        view.setEntries([
            GitConfigEntry(key: "user.name", value: "Mike"),
            GitConfigEntry(key: "user.email", value: "m@x.com")
        ])
        XCTAssertEqual(view.entries.count, 2)
        XCTAssertEqual(view.tableView.numberOfRows, 2)
    }

    func testCommittingAnEditedValueFiresOnSet() {
        let view = GitGlobalConfigTableView()
        view.setEntries([GitConfigEntry(key: "user.name", value: "Mike")])
        var received: (String, String)?
        view.onSet = { received = ($0, $1) }
        view.commitEdit(row: 0, key: "user.name", value: "Michael")
        XCTAssertEqual(received?.0, "user.name")
        XCTAssertEqual(received?.1, "Michael")
    }

    func testRemovingTheSelectedEntryFiresOnUnset() {
        let view = GitGlobalConfigTableView()
        view.setEntries([GitConfigEntry(key: "alias.st", value: "status")])
        var removed: String?
        view.onUnset = { removed = $0 }
        view.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        view.removeSelectedEntry()
        XCTAssertEqual(removed, "alias.st")
    }

    func testBeginAddingEntryAppendsAnEmptyRow() {
        let view = GitGlobalConfigTableView()
        view.setEntries([])
        view.beginAddingEntry()
        XCTAssertEqual(view.tableView.numberOfRows, 1)
        XCTAssertEqual(view.entries.first?.key, "")
    }

    func testShowErrorRevealsTheLabel() {
        let view = GitGlobalConfigTableView()
        view.showError("boom")
        XCTAssertFalse(view.errorLabel.isHidden)
        XCTAssertEqual(view.errorLabel.stringValue, "boom")
        view.showError("")
        XCTAssertTrue(view.errorLabel.isHidden)
    }

    func testPlaceholderRowHoldsUntilBothHalvesPresent() {
        let view = GitGlobalConfigTableView()
        view.setEntries([])
        view.beginAddingEntry()
        var received: (String, String)?
        view.onSet = { received = ($0, $1) }
        view.commitEdit(row: 0, key: "user.name", value: "")
        XCTAssertNil(received)
        view.commitEdit(row: 0, key: "user.name", value: "Mike")
        XCTAssertEqual(received?.0, "user.name")
        XCTAssertEqual(received?.1, "Mike")
    }

    func testClearingAnExistingRowsValueStillFiresOnSet() {
        let view = GitGlobalConfigTableView()
        view.setEntries([GitConfigEntry(key: "user.name", value: "Mike")])
        var received: (String, String)?
        view.onSet = { received = ($0, $1) }
        view.commitEdit(row: 0, key: "user.name", value: "")
        XCTAssertEqual(received?.0, "user.name")
        XCTAssertEqual(received?.1, "")
    }

    func testRenamingAnExistingKeyUnsetsTheOldKeyThenSetsTheNew() {
        let view = GitGlobalConfigTableView()
        view.setEntries([GitConfigEntry(key: "alias.st", value: "status")])
        var events: [String] = []
        view.onUnset = { events.append("unset:\($0)") }
        view.onSet = { events.append("set:\($0)=\($1)") }
        view.commitEdit(row: 0, key: "alias.s", value: "status")
        XCTAssertEqual(events, ["unset:alias.st", "set:alias.s=status"])
    }

    func testBlankingAnExistingKeyRevertsTheCell() {
        let view = GitGlobalConfigTableView()
        view.setEntries([GitConfigEntry(key: "alias.st", value: "status")])
        var setFired = false
        var unsetFired = false
        view.onSet = { _, _ in setFired = true }
        view.onUnset = { _ in unsetFired = true }
        view.commitEdit(row: 0, key: "", value: "status")
        XCTAssertFalse(setFired)
        XCTAssertFalse(unsetFired)
        XCTAssertEqual(view.entries.first?.key, "alias.st")
    }

    func testEndEditingFromADetachedFieldCommitsNothing() {
        let view = GitGlobalConfigTableView()
        view.setEntries([GitConfigEntry(key: "user.name", value: "Mike")])
        var setFired = false
        view.onSet = { _, _ in setFired = true }
        let detachedField = NSTextField(string: "typed-into-key")
        detachedField.tag = 0
        let notification = Notification(name: NSControl.textDidEndEditingNotification, object: detachedField)
        view.controlTextDidEndEditing(notification)
        XCTAssertFalse(setFired)
        XCTAssertEqual(view.entries.first?.value, "Mike")
    }

    func testAccessibilityIdentifierIsOnTheTableView() {
        let view = GitGlobalConfigTableView()
        XCTAssertEqual(view.tableView.accessibilityIdentifier(), "settings.git.config-table")
    }

    func testRemoveButtonDisabledAfterPlaceholderDiscarded() {
        let view = GitGlobalConfigTableView()
        view.setEntries([])
        view.beginAddingEntry()
        view.removeSelectedEntry()
        XCTAssertFalse(view.removeButton.isEnabled)
    }
}
