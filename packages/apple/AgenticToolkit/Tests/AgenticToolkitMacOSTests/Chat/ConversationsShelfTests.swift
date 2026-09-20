// Tests/AgenticToolkitMacOSTests/Chat/ConversationsShelfTests.swift
import AppKit
import XCTest
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The session shelf: which conversations the merged feed draws, and the list
/// beside it that decides.
///
/// What is worth testing here is the part that is invisible on screen. A shelf
/// with the wrong Select All scope still shows ticks; a filter that reads its
/// roster from its own output still lists rows; a roster taken after the sieve
/// still looks complete — right up until the session you hid is gone from the
/// list that was the only way to get it back.
@MainActor
final class ConversationsShelfTests: XCTestCase {

    /// A call counter a `@Sendable` closure may reach.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func bump() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    private func message(_ sourceID: String, name: String, context: [String] = []) -> ChatMessage {
        ChatMessage(
            role: .assistant,
            text: "hello from \(sourceID)",
            attribution: ChatMessage.Attribution(
                sourceID: sourceID,
                context: context,
                name: name,
                iconSymbol: "person"))
    }

    // MARK: - The model

    func testRosterIsEveryDistinctSessionInFirstAppearanceOrder() {
        let filter = ConversationsSessionFilter()
        _ = filter.apply(to: [
            message("b", name: "Beta"),
            message("a", name: "Alpha"),
            message("b", name: "Beta")
        ])
        XCTAssertEqual(filter.roster.map(\.id), ["b", "a"])
    }

    func testAHiddenSessionStaysOnTheRoster() {
        // The row is the only way back. A roster read from the filtered result
        // would delete it, and the session could never be shown again.
        let filter = ConversationsSessionFilter()
        let page = [message("a", name: "Alpha"), message("b", name: "Beta")]
        _ = filter.apply(to: page)
        filter.hidden = ["a"]

        let shown = filter.apply(to: page)
        XCTAssertEqual(shown.compactMap { $0.attribution?.sourceID }, ["b"])
        XCTAssertEqual(filter.roster.map(\.id), ["a", "b"])
    }

    func testASessionNobodyHasHiddenIsShown() {
        // Storing the hidden set rather than the shown one is what makes a
        // session that starts talking mid-window arrive already ticked.
        let filter = ConversationsSessionFilter()
        filter.hidden = ["a"]
        let shown = filter.apply(to: [message("a", name: "Alpha"), message("new", name: "New")])
        XCTAssertEqual(shown.compactMap { $0.attribution?.sourceID }, ["new"])
        XCTAssertTrue(filter.isShown("new"))
    }

    func testAMessageWithNoSessionIsNeverHidden() {
        // A notice the window wrote itself belongs to no row, so no row can
        // hide it.
        let filter = ConversationsSessionFilter()
        filter.hidden = ["a"]
        let notice = ChatMessage(role: .notice, text: "Feed unavailable")
        let shown = filter.apply(to: [message("a", name: "Alpha"), notice])
        XCTAssertEqual(shown.map(\.text), ["Feed unavailable"])
    }

    func testRosterChangeFiresOnlyWhenTheSessionsChange() {
        let filter = ConversationsSessionFilter()
        // A counting box rather than a captured `var`: the callback is
        // `@Sendable` because the poll that fires it is not on the main actor.
        let fired = Counter()
        filter.onRosterChanged = { _ in fired.bump() }
        let page = [message("a", name: "Alpha")]
        _ = filter.apply(to: page)
        _ = filter.apply(to: page + [message("a", name: "Alpha")])
        XCTAssertEqual(fired.value, 1, "a poll that only added messages rebuilt the shelf")

        _ = filter.apply(to: page + [message("b", name: "Beta")])
        XCTAssertEqual(fired.value, 2)
    }

    // MARK: - The shelf

    private func shelf(_ sessions: [(String, String)]) -> ConversationsShelfViewController {
        let shelf = ConversationsShelfViewController()
        _ = shelf.view
        shelf.sessions = sessions.map {
            ConversationsSessionFilter.Session(id: $0.0, name: $0.1, context: [])
        }
        return shelf
    }

    func testRowsAreSortedByName() {
        let shelf = shelf([("c", "Charlie"), ("a", "Alpha"), ("b", "Beta")])
        XCTAssertEqual(shelf.visibleSessions.map(\.name), ["Alpha", "Beta", "Charlie"])
    }

    func testTheFilterNarrowsTheList() {
        let shelf = shelf([("a", "Alpha"), ("b", "Beta")])
        shelf.filter = "bet"
        XCTAssertEqual(shelf.visibleSessions.map(\.id), ["b"])
    }

    func testTheFilterMatchesTheContextCrumbsToo() {
        // Typing a branch name finds the session on that branch, even though
        // the branch is not its name — the row draws it, so it is searchable.
        let shelf = ConversationsShelfViewController()
        _ = shelf.view
        shelf.sessions = [
            ConversationsSessionFilter.Session(
                id: "a", name: "Alpha", context: ["stenographer", "fix-login"]),
            ConversationsSessionFilter.Session(id: "b", name: "Beta", context: ["other"])
        ]
        shelf.filter = "fix-login"
        XCTAssertEqual(shelf.visibleSessions.map(\.id), ["a"])
    }

    func testUnselectAllLeavesFilteredAwaySessionsAlone() {
        // "All" typed into a search field means all of what you can see. A
        // menu that reached past the filter would undo a reader's narrowing
        // with one keystroke, invisibly.
        let shelf = shelf([("a", "Alpha"), ("b", "Beta")])
        shelf.filter = "alpha"
        shelf.unselectAllVisible()
        XCTAssertEqual(shelf.hidden, ["a"])
    }

    func testSelectAllOnlyRestoresTheVisibleSessions() {
        let shelf = shelf([("a", "Alpha"), ("b", "Beta")])
        shelf.unselectAllVisible()
        XCTAssertEqual(shelf.hidden, ["a", "b"])

        shelf.filter = "beta"
        shelf.selectAllVisible()
        XCTAssertEqual(shelf.hidden, ["a"])
    }

    func testTheHostHearsEveryChangeItDidNotMake() {
        let shelf = shelf([("a", "Alpha")])
        var reported: [Set<String>] = []
        shelf.onHiddenChanged = { reported.append($0) }

        shelf.unselectAllVisible()
        shelf.unselectAllVisible()  // already hidden — nothing changed
        shelf.selectAllVisible()
        XCTAssertEqual(reported, [["a"], []])

        // A restored selection is one the host already knows about.
        shelf.setHidden(["a"])
        XCTAssertEqual(reported.count, 2)
        XCTAssertEqual(shelf.hidden, ["a"])
    }

    func testANewRosterKeepsTheTicks() {
        // A session that falls off the page and comes back must not silently
        // reappear in the feed the reader hid it from.
        let shelf = shelf([("a", "Alpha"), ("b", "Beta")])
        shelf.unselectAllVisible()
        shelf.sessions = [
            ConversationsSessionFilter.Session(id: "a", name: "Alpha", context: []),
            ConversationsSessionFilter.Session(id: "c", name: "Charlie", context: [])
        ]
        XCTAssertEqual(shelf.hidden, ["a", "b"])
        XCTAssertEqual(shelf.visibleSessions.map(\.id), ["a", "c"])
    }

    func testTheShelfDrawsAnInsetRoundedPanel() {
        // The System Settings outline the window was asked for is this panel and
        // nothing else: a sidebar split item's own backdrop is square and runs
        // edge to edge, so the shape is ours to draw and ours to keep. A later
        // simplification that pinned the list straight to the shelf's root would
        // lose the look with nothing else going wrong to say so.
        let shelf = ConversationsShelfViewController()
        shelf.view.frame = NSRect(x: 0, y: 0, width: 220, height: 400)
        shelf.view.layoutSubtreeIfNeeded()

        guard let panel = shelf.view.subviews.compactMap({ $0 as? NSVisualEffectView }).first
        else { return XCTFail("the shelf drew no panel") }

        XCTAssertEqual(panel.material, .sidebar)
        XCTAssertGreaterThan(panel.layer?.cornerRadius ?? 0, 0, "square corners are not the outline")
        XCTAssertGreaterThan(panel.frame.minX, 0, "flush with the window edge is not inset")
        XCTAssertGreaterThan(panel.frame.minY, 0)
        XCTAssertLessThan(panel.frame.maxY, shelf.view.bounds.height)
    }

    // MARK: - The split

    func testTheShelfStartsAway() {
        let split = ConversationsSplitViewController(
            feed: ConversationsViewController { _, _ in [] })
        _ = split.view
        XCTAssertFalse(split.isShelfVisible)
    }

    func testTickingASessionOffReachesTheFeed() {
        let feed = ConversationsViewController { _, _ in [] }
        let split = ConversationsSplitViewController(feed: feed)
        _ = split.view
        split.shelf.sessions = [
            ConversationsSessionFilter.Session(id: "a", name: "Alpha", context: [])
        ]
        split.shelf.unselectAllVisible()
        XCTAssertEqual(feed.hiddenSessions, ["a"])
    }
}
