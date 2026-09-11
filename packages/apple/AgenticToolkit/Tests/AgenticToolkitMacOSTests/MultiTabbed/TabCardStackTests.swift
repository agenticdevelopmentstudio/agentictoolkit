import AgenticToolkitCore
import AppKit
import XCTest
@testable import AgenticToolkitMacOS

/// The tab cards as a deck: how far they overlap, how far each one stands from
/// the card in front, and which of them is drawn — and clicked — over which.
@MainActor
final class TabCardStackTests: XCTestCase {

    private final class StubSource: TabPaneDataSource {
        func tabPaneAgentName(_ pane: TabPaneViewController) -> String { "Claude" }
        func tabPaneModelName(_ pane: TabPaneViewController) -> String? { "Fable 5.1" }
        func tabPaneStatusSymbols(_ pane: TabPaneViewController) -> [TabPaneStatusSymbol] { [.idle] }
        func tabPaneSessionName(_ pane: TabPaneViewController) -> String { "tabs" }
        func tabPaneWorkingDirectory(_ pane: TabPaneViewController) -> URL {
            URL(fileURLWithPath: "/tmp/repo")
        }
        func tabPaneBranch(_ pane: TabPaneViewController) -> String? { "tabs" }
        func tabPaneSummary(_ pane: TabPaneViewController) -> String? { nil }
    }

    private let source = StubSource()

    private func makeBar(edge: Edge, cards: Int) -> (MultiTabbedViewController, [TabPaneViewController]) {
        let controller = MultiTabbedViewController()
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 900)
        let panes = (0..<cards).map { _ -> TabPaneViewController in
            let pane = TabPaneViewController(edge: edge, tabID: UUID())
            pane.dataSource = source
            pane.loadViewIfNeeded()
            pane.reload()
            let content = NSViewController()
            content.view = NSView()
            // The card carries its own id and the tab carries the bar's; a
            // selection is addressed to the latter, so they have to be one and
            // the same or nothing here selects anything.
            controller.addTab(
                .init(id: pane.tabID, item: .viewController(pane), viewController: content),
                on: edge
            )
            return pane
        }
        controller.view.layoutSubtreeIfNeeded()
        return (controller, panes)
    }

    /// The wrappers the bar built for its cards, in `subviews` order — which is
    /// back to front: the last one is drawn over the rest, and is the first
    /// offered a click.
    private func cardViews(_ controller: MultiTabbedViewController, on edge: Edge) -> [NSView] {
        controller.view.layoutSubtreeIfNeeded()
        return controller.tabBars[edge]?.subviews.first?.subviews ?? []
    }

    /// Which pane each of those wrappers is holding, in the same order.
    private func panes(of views: [NSView], among panes: [TabPaneViewController]) -> [Int] {
        views.compactMap { view in panes.firstIndex { $0.view.isDescendant(of: view) } }
    }

    /// The cards' order down the column, topmost first.
    private func columnOrder(_ views: [NSView], among panes: [TabPaneViewController]) -> [Int] {
        self.panes(of: views.sorted { $0.frame.maxY > $1.frame.maxY }, among: panes)
    }

    func testCardsOnAVerticalBarOverlapEachOther() {
        let (controller, panes) = makeBar(edge: .left, cards: 3)
        let column = cardViews(controller, on: .left).sorted { $0.frame.maxY > $1.frame.maxY }
        XCTAssertEqual(column.count, panes.count)
        for (upper, lower) in zip(column, column.dropFirst()) {
            XCTAssertEqual(lower.frame.maxY - upper.frame.minY, TabBarView.cardOverlap, accuracy: 0.5)
        }
    }

    /// A row of cards is laid out along their long side, where the window runs
    /// out before a stack has any depth to show — so they are spaced, not
    /// stacked.
    func testCardsOnAHorizontalBarDoNotOverlap() {
        let (controller, _) = makeBar(edge: .top, cards: 3)
        let row = cardViews(controller, on: .top).sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertEqual(row.count, 3)
        for (left, right) in zip(row, row.dropFirst()) {
            XCTAssertEqual(right.frame.minX - left.frame.maxX, TabBarView.itemSpacing, accuracy: 0.5)
        }
    }

    /// Where two cards overlap, the selected one is the one both the eye and
    /// the mouse land on: it is last in `subviews`, which is drawn last and hit
    /// tested first.
    func testTheSelectedCardIsDrawnOverTheCardsBehindIt() {
        let (controller, panes) = makeBar(edge: .left, cards: 3)
        controller.selectTab(id: panes[1].tabID, on: .left)
        let views = cardViews(controller, on: .left)
        XCTAssertEqual(self.panes(of: views, among: panes).last, 1)
        // Reordering the wrappers must leave the column itself alone: the deck
        // is turned, never reshuffled.
        XCTAssertEqual(columnOrder(views, among: panes), [0, 1, 2])
    }

    /// The cards behind are ordered among themselves too — nearer the front is
    /// nearer the top of the deck — so a card never shows through one standing
    /// further back than it.
    func testCardsBehindAreOrderedByHowFarBackTheyStand() {
        let (controller, panes) = makeBar(edge: .left, cards: 4)
        controller.selectTab(id: panes[0].tabID, on: .left)
        XCTAssertEqual(self.panes(of: cardViews(controller, on: .left), among: panes), [3, 2, 1, 0])
    }

    func testEveryCardIsToldHowFarItStandsFromTheSelectedOne() {
        let (controller, panes) = makeBar(edge: .left, cards: 4)
        controller.selectTab(id: panes[2].tabID, on: .left)
        XCTAssertEqual(panes.map(\.stackDepth), [2, 1, 0, 1])
    }
}
