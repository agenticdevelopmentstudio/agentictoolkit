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

    /// Renaming a live row fires `onRename` and *only* `onRename`.
    ///
    /// This deliberately replaced an earlier contract where a rename arrived as
    /// a separate `onUnset` followed by `onSet`. That shape could not be made
    /// safe: the two halves reached the panel as independent writes, so a set
    /// that failed after its unset had already succeeded left the user's real
    /// `~/.gitconfig` missing a setting with nothing left to restore it from.
    /// `onRename` carries both keys *and* both values, which is what lets the
    /// panel run the whole sequence as one operation and roll back.
    ///
    /// The assertion that `events` is exactly the rename — not merely that it
    /// contains it — is the load-bearing half. A rename that *also* fired the
    /// old pair would restore the very defect this replaced.
    func testRenamingAnExistingKeyFiresOnRenameAndNothingElse() {
        let view = GitGlobalConfigTableView()
        view.setEntries([GitConfigEntry(key: "alias.st", value: "status")])
        var events: [String] = []
        view.onUnset = { events.append("unset:\($0)") }
        view.onSet = { events.append("set:\($0)=\($1)") }
        view.onRename = { events.append("rename:\($0)=\($1)->\($2)=\($3)") }
        view.commitEdit(row: 0, key: "alias.s", value: "status")
        XCTAssertEqual(events, ["rename:alias.st=status->alias.s=status"])
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
