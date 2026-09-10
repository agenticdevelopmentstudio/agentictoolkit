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
}
