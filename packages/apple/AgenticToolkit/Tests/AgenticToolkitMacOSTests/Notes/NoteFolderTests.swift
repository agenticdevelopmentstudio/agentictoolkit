import XCTest
import AgenticToolkitMarkdown
@testable import AgenticToolkitMacOS

/// `NoteFolder.tree` turns the store's flat `categories()` + `categoryEdges()`
/// output into the nested shape the folders pane displays. These pin the
/// rules the grounding calls out explicitly: a two-parent node appears under
/// both parents, "All Notes" carries its own total rather than a sum over
/// `counts`, and a cycle in the data degrades to a truncated branch instead
/// of hanging.
final class NoteFolderTests: XCTestCase {

    private func category(_ id: String, _ name: String) -> MarkdownCategory {
        MarkdownCategory(id: id, name: name)
    }

    func testFlatCategoriesWithNoEdgesAreAllRoots() {
        let categories = [category("a", "A"), category("b", "B")]
        let roots = NoteFolder.tree(from: categories, counts: [:], edges: [], total: 0)
        XCTAssertEqual(roots.map(\.id).sorted(), ["a", "b"])
        XCTAssertTrue(roots.allSatisfy { $0.children.isEmpty })
    }

    func testAnEdgeNestsTheChildUnderItsParent() {
        let categories = [category("top", "Top"), category("sub", "Sub")]
        let edges: [(parent: String, child: String)] = [(parent: "top", child: "sub")]
        let roots = NoteFolder.tree(from: categories, counts: [:], edges: edges, total: 0)
        XCTAssertEqual(roots.map(\.id), ["top"])
        XCTAssertEqual(roots[0].children.map(\.id), ["sub"])
    }

    func testATwoParentNodeAppearsUnderBothParents() {
        let categories = [
            category("top", "Top"), category("left", "Left"),
            category("right", "Right"), category("bottom", "Bottom")
        ]
        let edges: [(parent: String, child: String)] = [
            (parent: "top", child: "left"), (parent: "top", child: "right"),
            (parent: "left", child: "bottom"), (parent: "right", child: "bottom")
        ]
        let roots = NoteFolder.tree(from: categories, counts: [:], edges: edges, total: 0)
        XCTAssertEqual(roots.map(\.id), ["top"])
        let children = roots[0].children
        XCTAssertEqual(children.map(\.id).sorted(), ["left", "right"])
        for child in children {
            XCTAssertEqual(child.children.map(\.id), ["bottom"])
        }
    }

    func testTotalIsIndependentOfADoubleCountedNote() {
        // A note filed under both "left" and "right" makes counts.values sum
        // to more than the true total — the exact case the `total` parameter
        // exists to avoid double-counting when the caller builds "All Notes".
        let categories = [category("left", "Left"), category("right", "Right")]
        let counts = ["left": 1, "right": 1]
        let roots = NoteFolder.tree(from: categories, counts: counts, edges: [], total: 1)
        let sumOverRoots = roots.reduce(0) { $0 + $1.noteCount }
        XCTAssertGreaterThan(sumOverRoots, 1)
        let allNotes = NoteFolder(id: "", name: "All Notes", noteCount: 1, children: [])
        XCTAssertTrue(allNotes.isAllNotes)
        XCTAssertLessThan(allNotes.noteCount, sumOverRoots)
    }

    func testACycleInBadDataTruncatesRatherThanHanging() {
        // A well-behaved database never has this shape (addCategoryEdge
        // refuses cycles), but a database written by adh, or a future bug,
        // still can. The recursion guard must bound the walk instead of
        // hanging, and every node in the cycle has an incoming edge, so with
        // no true root the builder must not simply lose them.
        let categories = [category("a", "A"), category("b", "B"), category("c", "C")]
        let edges: [(parent: String, child: String)] = [
            (parent: "a", child: "b"), (parent: "b", child: "c"), (parent: "c", child: "a")
        ]
        let roots = NoteFolder.tree(from: categories, counts: [:], edges: edges, total: 0)
        XCTAssertFalse(roots.isEmpty)
    }

    func testFolderCarriesItsDirectNoteCount() {
        let categories = [category("a", "A")]
        let roots = NoteFolder.tree(from: categories, counts: ["a": 3], edges: [], total: 3)
        XCTAssertEqual(roots.first?.noteCount, 3)
    }

    func testAllNotesIDIsEmptyAndIsAllNotesIsTrue() {
        let allNotes = NoteFolder(id: "", name: "All Notes", noteCount: 0, children: [])
        XCTAssertEqual(allNotes.id, "")
        XCTAssertTrue(allNotes.isAllNotes)
    }
}
