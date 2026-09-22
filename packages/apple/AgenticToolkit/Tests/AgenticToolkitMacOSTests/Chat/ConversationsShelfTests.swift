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

    // MARK: - Page depth

    /// Ticking a session off must not shorten the feed. The source answers with
    /// the newest N entries across every session, so hiding most of them leaves
    /// a fraction of a page: the reader asked to see one conversation more
    /// clearly and got less timeline.
    func testHidingMostOfAPageAsksTheNextReadToGoDeeper() {
        let filter = ConversationsSessionFilter()
        XCTAssertEqual(filter.pageDeepening, 1, "an unfiltered feed read deeper than a page")

        filter.hidden = ["a", "b", "c"]
        let page = (0..<4).flatMap { _ in
            [message("a", name: "Alpha"), message("b", name: "Beta"),
             message("c", name: "Gamma"), message("d", name: "Delta")]
        }
        XCTAssertEqual(filter.apply(to: page).count, 4)
        XCTAssertEqual(filter.pageDeepening, 4,
                       "a page that lost three quarters of its rows asked for the same depth again")
    }

    /// The ceiling exists because the source's scan is finite: past a point a
    /// deeper request costs more and returns the same rows.
    func testAPageThatLostEverythingAsksForTheMostAllowed() {
        let filter = ConversationsSessionFilter()
        filter.hidden = ["a"]
        _ = filter.apply(to: [message("a", name: "Alpha")])
        XCTAssertEqual(filter.pageDeepening, ConversationsSessionFilter.maxPageDeepening)
    }

    /// It is a ratio inside one page, so it must not compound — a deeper page
    /// that drops the same share asks for the same depth, not for more.
    func testUnhidingEverythingGoesBackToOnePage() {
        let filter = ConversationsSessionFilter()
        filter.hidden = ["a"]
        _ = filter.apply(to: [message("a", name: "Alpha"), message("b", name: "Beta")])
        XCTAssertGreaterThan(filter.pageDeepening, 1)

        filter.hidden = []
        _ = filter.apply(to: [message("a", name: "Alpha"), message("b", name: "Beta")])
        XCTAssertEqual(filter.pageDeepening, 1,
                       "a feed with nothing hidden kept re-reading a multiple of its page")
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

    func testARowIsTitledByWhereTheSessionIsNotWhatItIsCalled() {
        // A session's name is a summary of what it is doing this minute
        // ("editing AccountQuotaStore") and rewrites itself under the reader.
        // Its project and branch do not.
        let session = ConversationsSessionFilter.Session(
            id: "a", name: "editing AccountQuotaStore", context: ["stenographer", "conversations"])
        XCTAssertEqual(session.displayName, "stenographer >> conversations")

        // And a session with nowhere to be is still titled by something.
        let placeless = ConversationsSessionFilter.Session(id: "b", name: "Beta", context: [])
        XCTAssertEqual(placeless.displayName, "Beta")
    }

    func testRowsAreSortedByTheTitleTheyDraw() {
        // Sorting on the name while drawing the place gives a list in an order
        // nobody looking at it can see.
        let shelf = ConversationsShelfViewController()
        _ = shelf.view
        shelf.sessions = [
            ConversationsSessionFilter.Session(id: "a", name: "Zebra", context: ["alpha", "main"]),
            ConversationsSessionFilter.Session(id: "b", name: "Apple", context: ["zulu", "main"])
        ]
        XCTAssertEqual(shelf.visibleSessions.map(\.displayName), ["alpha >> main", "zulu >> main"])
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

    func testTheShelfDrawsAnInsetRoundedPanelFromThePalette() {
        // Two things at once, because they are one decision: the System
        // Settings outline is ours to draw (a sidebar split item's backdrop is
        // square and full-bleed), and it is drawn from the *theme* — the
        // system's sidebar material reaches no palette, so a custom theme had a
        // grey-blue plane down the window's left belonging to none of it.
        let shelf = ConversationsShelfViewController()
        shelf.view.frame = NSRect(x: 0, y: 0, width: 260, height: 400)
        shelf.view.layoutSubtreeIfNeeded()

        guard let panel = shelf.view.subviews.compactMap({ $0 as? ThemedBox }).first
        else { return XCTFail("the shelf drew no themed panel") }

        XCTAssertEqual(panel.fillRole, .surface)
        XCTAssertGreaterThan(panel.layer?.cornerRadius ?? 0, 0, "square corners are not the outline")
        XCTAssertGreaterThan(panel.frame.minX, 0, "flush with the window edge is not inset")
        XCTAssertGreaterThan(panel.frame.minY, 0)
        XCTAssertLessThan(panel.frame.maxY, shelf.view.bounds.height)

        XCTAssertFalse(
            shelf.view.subviews.contains { $0 is NSVisualEffectView },
            "system material is not the theme")
    }

    func testTheListHasNoSystemDrawnHeader() {
        // `NSTableHeaderView` is drawn by the system to its last pixel and
        // reaches no palette. The sort control is the themed header above the
        // list instead — so if this ever comes back, the sort moved with it.
        let shelf = shelf([("a", "Alpha")])
        let table = firstTable(in: shelf.view)
        XCTAssertNotNil(table)
        XCTAssertNil(table?.headerView)
    }

    func testTheShelfOpensWideEnoughToReadASessionsPlace() {
        // A list of names cut off at the project is a list you cannot tell two
        // branches apart in, which is the whole job of the shelf.
        let shelf = ConversationsShelfViewController()
        _ = shelf.view
        let fitting = shelf.view.fittingSize.width
        XCTAssertGreaterThanOrEqual(fitting, 240, "the shelf opens too narrow to read a row")
    }

    private func firstTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for subview in view.subviews {
            if let found = firstTable(in: subview) { return found }
        }
        return nil
    }

    /// Every string a view hierarchy actually draws, in no particular order.
    private func texts(in view: NSView) -> [String] {
        var found: [String] = []
        if let field = view as? NSTextField, !field.stringValue.isEmpty {
            found.append(field.stringValue)
        }
        for subview in view.subviews { found += texts(in: subview) }
        return found
    }

    /// The `name` column's cell for a row, built the way the table builds it.
    private func nameCell(
        of shelf: ConversationsShelfViewController, row: Int
    ) -> NSView? {
        guard let table = firstTable(in: shelf.view),
              let column = table.tableColumns.first(where: { $0.identifier.rawValue == "name" })
        else { return nil }
        return shelf.tableView(table, viewFor: column, row: row)
    }

    /// The first ``SessionHeaderView`` in a hierarchy — the shared control the
    /// Sessions window, the shelf and each bubble are all supposed to be drawing.
    private func header(in view: NSView) -> SessionHeaderView? {
        if let header = view as? SessionHeaderView { return header }
        for subview in view.subviews {
            if let found = header(in: subview) { return found }
        }
        return nil
    }

    func testARowDrawsTheWholeTrailInTheSharedHeader() {
        // The shelf used to put two crumbs in the header and the name on a
        // caption line beneath it, so one session read as "stenographer" here
        // and "stenographer » conversations » editing…" in the Sessions window.
        // Same control, different arguments — which is not sharing a control.
        let shelf = ConversationsShelfViewController()
        _ = shelf.view
        shelf.sessions = [ConversationsSessionFilter.Session(
            id: "a",
            name: "editing AccountQuotaStore",
            context: ["stenographer", "conversations"])]

        guard let cell = nameCell(of: shelf, row: 0) else { return XCTFail("no name cell") }
        guard let header = header(in: cell) else { return XCTFail("no shared header") }
        let inHeader = texts(in: header)
        XCTAssertTrue(inHeader.contains("stenographer"), "the header lost its project: \(inHeader)")
        XCTAssertTrue(inHeader.contains("conversations"), "the header lost its branch: \(inHeader)")
        XCTAssertTrue(inHeader.contains("editing AccountQuotaStore"),
                      "the name is not in the trail: \(inHeader)")
        // And nowhere else: a caption repeating the name is the row saying the
        // same thing twice, which is what the second line had become.
        XCTAssertEqual(texts(in: cell).count, inHeader.count,
                       "the row draws text outside the shared header: \(texts(in: cell))")
    }

    func testAnUnnamedSessionDoesNotEndItsTrailWithItsId() {
        // `Session` falls back to the id when there is no name, which is the
        // right answer for a row that would otherwise be blank and the wrong
        // one for the end of a trail.
        let shelf = ConversationsShelfViewController()
        _ = shelf.view
        shelf.sessions = [ConversationsSessionFilter.Session(
            id: "3f7c1a9e-0000", name: "", context: ["stenographer", "main"])]

        guard let cell = nameCell(of: shelf, row: 0) else { return XCTFail("no name cell") }
        let drawn = texts(in: cell)
        XCTAssertEqual(drawn.filter { $0.contains("3f7c1a9e") }, [], "the id is drawn: \(drawn)")
        XCTAssertTrue(drawn.contains("stenographer"), "the row lost its project: \(drawn)")

        // But a session with nowhere to be at all still draws something.
        shelf.sessions = [ConversationsSessionFilter.Session(
            id: "3f7c1a9e-0000", name: "", context: [])]
        guard let placeless = nameCell(of: shelf, row: 0) else { return XCTFail("no name cell") }
        XCTAssertEqual(texts(in: placeless), ["3f7c1a9e-0000"])
    }

    func testARowDrawsNoActivityGlyphUntilTheSourceSaysOtherwise() {
        // The roster is built out of what was *said*, so it carries no live
        // state: a shelf nobody has given a source to draws no glyphs at all,
        // rather than a column of idle ones.
        let shelf = ConversationsShelfViewController()
        _ = shelf.view
        shelf.sessions = [ConversationsSessionFilter.Session(
            id: "a", name: "Alpha", context: ["stenographer", "main"])]

        guard let cell = nameCell(of: shelf, row: 0) else { return XCTFail("no name cell") }
        guard let glyph = activityIcon(in: cell) else { return XCTFail("no activity view") }
        XCTAssertTrue(glyph.isHidden, "an idle session is drawing a glyph")

        shelf.activity = ["a": .working]
        XCTAssertFalse(glyph.isHidden, "a working session is drawing nothing")
    }

    func testActivityReachesRowsThatAreAlreadyOnScreen() {
        // Rebuilding the table every poll would restart each animation from its
        // first frame, so the state is pushed into the glyphs in place.
        let shelf = ConversationsShelfViewController()
        _ = shelf.view
        shelf.sessions = [ConversationsSessionFilter.Session(
            id: "a", name: "Alpha", context: ["stenographer", "main"])]
        shelf.activity = ["a": .working]

        guard let cell = nameCell(of: shelf, row: 0) else { return XCTFail("no name cell") }
        guard let glyph = activityIcon(in: cell) else { return XCTFail("no activity view") }
        XCTAssertFalse(glyph.isHidden)

        shelf.activity = ["a": .idle]
        XCTAssertTrue(glyph.isHidden, "the glyph kept drawing after the session went quiet")
    }

    /// The first activity glyph in a hierarchy.
    private func activityIcon(in view: NSView) -> SessionWatcher.SessionWatcherActivityIconView? {
        if let icon = view as? SessionWatcher.SessionWatcherActivityIconView { return icon }
        for subview in view.subviews {
            if let found = activityIcon(in: subview) { return found }
        }
        return nil
    }

    func testARowTitledByItsNameDoesNotDrawItTwice() {
        // A session with nowhere to be is titled by its name, so a summary line
        // saying the same thing again is the row repeating itself.
        let shelf = shelf([("a", "Alpha")])
        guard let cell = nameCell(of: shelf, row: 0) else { return XCTFail("no name cell") }
        XCTAssertEqual(texts(in: cell).filter { $0 == "Alpha" }.count, 1)
    }

    func testARowIsTallEnoughForTheIconTheSessionsWindowDraws() {
        // `usesAutomaticRowHeights` measures the row through the cell's own
        // constraints: a centred child leaves that chain open, and the row then
        // falls back to a fixed height that crops the app icon.
        let shelf = ConversationsShelfViewController()
        _ = shelf.view
        shelf.sessions = [ConversationsSessionFilter.Session(
            id: "a", name: "editing AccountQuotaStore",
            context: ["stenographer", "main"], appIdentity: "iTerm.app")]

        guard let cell = nameCell(of: shelf, row: 0) else { return XCTFail("no name cell") }
        // The Sessions window's 28pt icon plus this shelf's padding above and
        // below it. Smaller than that and the shared control is being drawn at
        // two sizes, which is two controls to a reader.
        XCTAssertGreaterThanOrEqual(cell.fittingSize.height, 28 + 7 + 7,
                                    "the row is too short for the icon the Sessions window draws")
    }

    // MARK: - The split

    func testTheShelfStartsAway() {
        let split = ConversationsSplitViewController(
            feed: ConversationsViewController { _, _, _ in [] })
        _ = split.view
        XCTAssertFalse(split.isShelfVisible)
    }

    func testTheListHasNoWidthCeiling() {
        // A maximum on the shelf is the app deciding how much of the window the
        // list may have, and a reader who drags past it is sprung back by a
        // pane refusing a width it could perfectly well be drawn at. AppKit
        // spells "no maximum" as `unspecifiedDimension`, not as zero — zero is
        // a real ceiling, and asserting on it passes only by accident.
        let split = ConversationsSplitViewController(
            feed: ConversationsViewController { _, _, _ in [] })
        _ = split.view
        guard let shelfItem = split.splitViewItems.first else { return XCTFail("no shelf item") }
        XCTAssertEqual(
            shelfItem.maximumThickness,
            NSSplitViewItem.unspecifiedDimension,
            "the session list is capped")
    }

    func testSwitchingToSingleModeShowsTheList() {
        // Single mode is steered from the list — a click picks the one
        // conversation, ⌘↑/⌘↓ walk it — so a mode switch that leaves the shelf
        // away strands the reader on whichever session was showing.
        let split = ConversationsSplitViewController(
            feed: ConversationsViewController { _, _, _ in [] })
        _ = split.view
        XCTAssertFalse(split.isShelfVisible)

        split.selectionMode = .single
        XCTAssertTrue(split.isShelfVisible, "single mode left the session list hidden")

        // And going back is not a toggle: multi mode leaves the list where the
        // reader had it rather than putting it away again.
        split.selectionMode = .multi
        XCTAssertTrue(split.isShelfVisible)
    }

    func testDisclosingTheShelfDoesNotResizeTheWindow() {
        // The default collapse behaviour resizes the split view and holds the
        // siblings fixed — and the split view here *is* the window's content,
        // so the window jumped 260 points wider every time the shelf came out.
        let split = ConversationsSplitViewController(
            feed: ConversationsViewController { _, _, _ in [] })
        _ = split.view

        guard let shelfItem = split.splitViewItems.first else { return XCTFail("no shelf item") }
        XCTAssertEqual(shelfItem.collapseBehavior, .preferResizingSiblingsWithFixedSplitView)

        // And the two minimums together have to fit inside the window's own
        // minimum width, or AppKit widens the window whatever the behaviour
        // says. 380 is the Conversations window's minimum.
        let minimums = split.splitViewItems.map(\.minimumThickness).reduce(0, +)
        XCTAssertLessThanOrEqual(minimums, 380)
    }

    func testTickingASessionOffReachesTheFeed() {
        let feed = ConversationsViewController { _, _, _ in [] }
        let split = ConversationsSplitViewController(feed: feed)
        _ = split.view
        split.shelf.sessions = [
            ConversationsSessionFilter.Session(id: "a", name: "Alpha", context: [])
        ]
        split.shelf.unselectAllVisible()
        XCTAssertEqual(feed.hiddenSessions, ["a"])
    }

    /// A remembered hidden set is set on the feed before the window is built, so
    /// the shelf has to be told as well. Left out, the feed draws four sessions
    /// and the shelf ticks all five — and the row the reader unticked last time
    /// is back with its box on, saying the opposite of what the timeline shows.
    func testAFeedThatAlreadyHidesASessionStartsWithItsShelfRowUnticked() {
        let feed = ConversationsViewController { _, _, _ in [] }
        feed.hiddenSessions = ["a"]
        let split = ConversationsSplitViewController(feed: feed)
        _ = split.view
        XCTAssertEqual(split.shelf.hidden, ["a"],
                       "the shelf ticked a session the feed was already hiding")
    }
}
