import AppKit
import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class PaneViewControllerTests: XCTestCase {

    /// Windows created by `loadedPane` to give the pane's view a real window —
    /// `NSPopover.show` (the minimize picker) throws "view has no window"
    /// without one. Held here, the same way `ChatViewFocusTests` and
    /// `WindowConfigPopoverTests.rebuildRereadsTheState` hold theirs, and torn
    /// down after each test.
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows { window.orderOut(nil) }
        windows = []
        try await super.tearDown()
    }

    /// Content that opts into everything, so each surface can be shown to be
    /// driven by the protocol.
    private final class RichContent: NSViewController,
        PaneTitleProviding, PaneAccessoryProviding, PaneOptionsProviding,
        PaneMinimizedRepresenting, PaneSearchable, PaneSelectionDescribing {

        var paneTitle = "Files" { didSet { onPaneTitleChange?() } }
        var onPaneTitleChange: (() -> Void)?
        var paneSelectionDescription: String? = "src/main.swift" {
            didSet { onPaneSelectionChange?() }
        }
        var onPaneSelectionChange: (() -> Void)?
        let paneSearchPlaceholder = "Filter files"
        private(set) var receivedQueries: [String] = []
        let accessory = NSButton()
        /// Held rather than built fresh per call, so a test can assert the pane
        /// hands back *these* rows and not merely two of something.
        let optionRows = [NSButton(), NSButton()]

        func makePaneAccessoryViews() -> [NSView] { [accessory] }
        func makePaneOptionRows() -> [NSView] { optionRows }
        var paneMinimizedSymbolName: String { "folder" }
        var paneMinimizedTooltip: String { "Files" }
        func paneSearch(for query: String) { receivedQueries.append(query) }
    }

    /// Content that opts into nothing — the reason every fallback exists.
    private final class BareContent: NSViewController {}

    private final class TestPane: PaneViewController {
        let content: NSViewController
        init(content: NSViewController, stateStore: PaneStateStore = EphemeralPaneStateStore()) {
            self.content = content
            super.init(stateStore: stateStore)
        }
        override func makeContentViewController() -> NSViewController? { content }
        override var fallbackTitle: String { "Untitled Pane" }
    }

    private final class SpyHost: PaneHost {
        var edges: Set<PaneEdge> = [.leading, .trailing]
        private(set) var closes = 0
        private(set) var zooms = 0
        private(set) var restores = 0
        private(set) var minimizeRequests: [PaneEdge] = []

        func paneDidRequestClose(_ pane: PaneViewController) { closes += 1 }
        func paneDidRequestZoom(_ pane: PaneViewController) { zooms += 1 }
        func paneDidRequestRestore(_ pane: PaneViewController) { restores += 1 }
        func paneDidRequestMinimize(_ pane: PaneViewController, to edge: PaneEdge) {
            minimizeRequests.append(edge)
        }
        func availableMinimizeEdges(for pane: PaneViewController) -> Set<PaneEdge> { edges }
    }

    private func loadedPane(
        content: NSViewController,
        store: PaneStateStore = EphemeralPaneStateStore()
    ) -> (TestPane, SpyHost) {
        let pane = TestPane(content: content, stateStore: store)
        let host = SpyHost()
        pane.host = host
        pane.loadViewIfNeeded()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = pane.view
        windows.append(window)

        return (pane, host)
    }

    // MARK: - Mounting

    func testTheContentIsAChildAndTheTitleBarIsOnTop() {
        let (pane, _) = loadedPane(content: RichContent())
        XCTAssertTrue(pane.children.contains { $0 === pane.contentViewController })
        XCTAssertTrue(pane.view.subviews.contains { $0 === pane.titleBar })
        XCTAssertEqual(pane.view.accessibilityIdentifier(), "pane")
    }

    // MARK: - Title

    func testTitleComesFromTheContentAndFollowsItsChanges() {
        let content = RichContent()
        let (pane, _) = loadedPane(content: content)
        XCTAssertEqual(pane.resolvedTitle, "Files")
        XCTAssertEqual(pane.titleBar.title, "Files")

        content.paneTitle = "Sources"
        XCTAssertEqual(pane.titleBar.title, "Sources",
                       "the pane installed its own callback rather than polling")
    }

    func testContentWithNoTitleFallsBackToTheSubclassesName() {
        let (pane, _) = loadedPane(content: BareContent())
        XCTAssertEqual(pane.resolvedTitle, "Untitled Pane")
        XCTAssertEqual(pane.titleBar.title, "Untitled Pane")
    }

    // MARK: - Accessories and options

    func testAccessoriesAndOptionRowsComeFromTheContent() {
        let content = RichContent()
        let (pane, _) = loadedPane(content: content)
        XCTAssertEqual(pane.titleBar.accessoryViews.count, 1)
        XCTAssertTrue(pane.titleBar.accessoryViews.first === content.accessory)

        // The gear leads with the two universal spacing rows (Task 14), then
        // the content's own. Asserted by identity, so four generic rows cannot
        // pass on the count alone; the spacing pair is rebuilt on every call,
        // so it is named by type and identifier rather than by instance.
        let rows = pane.makeOptionRows()
        XCTAssertEqual(rows.count, 4)
        XCTAssertTrue(rows.first is SpacingControl)
        XCTAssertEqual(rows[1].accessibilityIdentifier(), "pane.options.spacing.reset")
        XCTAssertTrue(rows[2] === content.optionRows[0])
        XCTAssertTrue(rows[3] === content.optionRows[1])
    }

    func testBareContentGetsNoAccessoriesAndOnlyTheUniversalOptionRows() {
        let (pane, _) = loadedPane(content: BareContent())
        XCTAssertTrue(pane.titleBar.accessoryViews.isEmpty)

        // Content that opts into nothing still gets the spacing pair every pane
        // has, and nothing past it.
        let rows = pane.makeOptionRows()
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.first is SpacingControl)
        XCTAssertEqual(rows[1].accessibilityIdentifier(), "pane.options.spacing.reset")
    }

    func testTheGearIsInTheTitleBarsTrailingSlot() {
        let (pane, _) = loadedPane(content: BareContent())
        XCTAssertNotNil(pane.titleBar.gearView)
    }

    /// A pane with nothing of its own to offer raises a menu of exactly one
    /// item — no leading separator, because there is nothing to separate it
    /// from.
    func testABarePanesGearMenuIsOnlySettings() {
        let (pane, _) = loadedPane(content: BareContent())

        let menu = pane.makeOptionsMenu()
        XCTAssertEqual(menu.items.count, 1)
        XCTAssertEqual(menu.items.first?.title, "Settings…")
        XCTAssertEqual(menu.items.first?.accessibilityIdentifier(), "pane.options.settings")
    }

    /// A pane that has its own items gets them above `Settings…`, separated —
    /// and every item is enabled on its own say-so, since a menu raised from a
    /// button has nothing to validate it.
    func testAPanesOwnItemsComeFirstAndSettingsLast() {
        final class ItemPane: PaneViewController {
            override func makeMenuItems() -> [NSMenuItem] {
                [NSMenuItem(title: "Move", action: nil, keyEquivalent: "")]
            }
        }

        let pane = ItemPane()
        pane.loadViewIfNeeded()

        let menu = pane.makeOptionsMenu()
        XCTAssertFalse(menu.autoenablesItems, "nothing validates a menu raised from a button")
        XCTAssertEqual(menu.items.map(\.title), ["Move", "", "Settings…"])
        XCTAssertTrue(menu.items[1].isSeparatorItem)
    }

    // MARK: - Requests go to the host

    func testCloseAndZoomAreRequestsNotActions() {
        let (pane, host) = loadedPane(content: BareContent())

        pane.titleBar.controls.closeButton.performClick(nil)
        XCTAssertEqual(host.closes, 1)

        pane.titleBar.controls.zoomButton.performClick(nil)
        XCTAssertEqual(host.zooms, 1)
        XCTAssertFalse(pane.isZoomed, "a click asks; only the host's answer changes state")
    }

    func testMinimizeOpensThePickerOverTheEdgesTheHostAllows() {
        let (pane, host) = loadedPane(content: BareContent())
        host.edges = [.top, .bottom]
        pane.titleBar.controls.minimizeButton.performClick(nil)

        let cross = try? XCTUnwrap(pane.minimizePicker?.crossView)
        XCTAssertEqual(cross?.availableEdges, [.top, .bottom])
        XCTAssertTrue(cross?.button(for: .top).isEnabled == true)
        XCTAssertTrue(cross?.button(for: .leading).isEnabled == false)
    }

    func testPickingAnEdgeAsksTheHostAndChangesNothingYet() {
        let (pane, host) = loadedPane(content: BareContent())
        pane.titleBar.controls.minimizeButton.performClick(nil)
        pane.minimizePicker?.crossView.button(for: .leading).performClick(nil)

        XCTAssertEqual(host.minimizeRequests, [.leading])
        XCTAssertNil(pane.minimizedEdge)
    }

    func testAPaneWithNowhereToGoShowsADisabledMinimizeControl() {
        let (pane, host) = loadedPane(content: BareContent())
        host.edges = []
        pane.refreshControlAvailability()
        XCTAssertFalse(pane.titleBar.controls.minimizeButton.isEnabled)
    }

    // MARK: - State the host hands back

    func testMinimizingSidewaysReplacesTheChromeWithARail() {
        let (pane, _) = loadedPane(content: RichContent())
        pane.setMinimized(to: .leading)

        XCTAssertEqual(pane.minimizedEdge, .leading)
        XCTAssertTrue(pane.titleBar.isHidden)
        let strip = pane.view.subviews.compactMap { $0 as? PaneMinimizedStripView }.first
        XCTAssertNotNil(strip)
        XCTAssertEqual(strip?.symbolName, "folder", "the rail draws the content's own glyph")
        XCTAssertEqual(strip?.tooltip, "Files")
    }

    func testMinimizingVerticallyLeavesTheTitleBarAndHidesTheContent() {
        let (pane, _) = loadedPane(content: RichContent())
        pane.setMinimized(to: .top)

        XCTAssertFalse(pane.titleBar.isHidden)
        XCTAssertTrue(pane.titleBar.controls.isMinimized)
        XCTAssertNil(pane.view.subviews.compactMap { $0 as? PaneMinimizedStripView }.first)
        XCTAssertTrue(pane.contentViewController?.view.isHidden == true)
    }

    func testRestoringPutsEverythingBack() {
        let (pane, _) = loadedPane(content: RichContent())
        pane.setMinimized(to: .leading)
        pane.setMinimized(to: nil)

        XCTAssertNil(pane.minimizedEdge)
        XCTAssertFalse(pane.titleBar.isHidden)
        XCTAssertFalse(pane.titleBar.controls.isMinimized)
        XCTAssertNil(pane.view.subviews.compactMap { $0 as? PaneMinimizedStripView }.first)
        XCTAssertTrue(pane.contentViewController?.view.isHidden == false)
    }

    /// The reachable path is a rebuild that moves the pane across its parent's
    /// slots: `reapplyPaneState()` re-resolves the edge from `isFirst` and
    /// hands the leaf the other horizontal edge, with no restore in between —
    /// so neither call takes the `guard edge.isHorizontal` teardown, and a
    /// strip that is merely re-shown keeps the dock constraint and the hairline
    /// side it was built with.
    func testFlippingTheRailToTheOtherSideRebuildsIt() throws {
        let (pane, _) = loadedPane(content: RichContent())

        pane.setMinimized(to: .leading)
        pane.view.layoutSubtreeIfNeeded()
        let first = try XCTUnwrap(pane.view.subviews.compactMap { $0 as? PaneMinimizedStripView }.first)
        XCTAssertEqual(first.frame.minX, 0, accuracy: 0.5, "docked to the pane's leading edge")

        pane.setMinimized(to: .trailing)
        pane.view.layoutSubtreeIfNeeded()
        let strips = pane.view.subviews.compactMap { $0 as? PaneMinimizedStripView }
        XCTAssertEqual(strips.count, 1, "the old rail was taken out, not left underneath")
        let second = try XCTUnwrap(strips.first)
        XCTAssertFalse(second === first,
                       "the rail is rebuilt for the new edge rather than re-shown")
        XCTAssertEqual(second.frame.maxX, pane.view.bounds.width, accuracy: 0.5,
                       "and it is docked to the trailing edge it was asked for")
    }

    func testRestoreFromTheRailAsksTheHost() {
        let (pane, host) = loadedPane(content: BareContent())
        pane.setMinimized(to: .trailing)
        let strip = pane.view.subviews.compactMap { $0 as? PaneMinimizedStripView }.first
        XCTAssertEqual(strip?.symbolName, PaneMinimizedStripView.defaultSymbolName,
                       "content with no minimized representation gets the generic glyph")
        XCTAssertEqual(strip?.tooltip, pane.resolvedTitle,
                       "and falls back to the pane's own title for the rail's tooltip")
        strip?.restoreButton.performClick(nil)
        XCTAssertEqual(host.restores, 1)
    }

    func testZoomStateFlipsTheGlyphOnly() {
        let (pane, _) = loadedPane(content: BareContent())
        pane.setZoomed(true)
        XCTAssertTrue(pane.isZoomed)
        XCTAssertTrue(pane.titleBar.controls.isZoomed)
    }

    /// The four pins that hold the content to its container, counted off the
    /// view they are installed on — deactivating removes them from it, so the
    /// count is the state.
    private func activeContentPins(of pane: TestPane) throws -> Int {
        let content = try XCTUnwrap(pane.contentViewController?.view)
        let container = try XCTUnwrap(content.superview)
        return container.constraints.filter {
            ($0.firstItem === content || $0.secondItem === content) && $0.isActive
        }.count
    }

    /// Hidden is not un-laid-out: content with its own minimum size goes on
    /// demanding it from a container squeezed to a rail's width, and the engine
    /// breaks whichever constraint it likes to get out.
    func testMinimizedContentIsTakenOutOfTheLayoutAndPutBack() throws {
        let (pane, _) = loadedPane(content: RichContent())
        XCTAssertEqual(try activeContentPins(of: pane), 4)

        pane.setMinimized(to: .leading)
        XCTAssertEqual(try activeContentPins(of: pane), 0,
                       "a rail-width container is asked to satisfy nothing")

        pane.setMinimized(to: .top)
        XCTAssertEqual(try activeContentPins(of: pane), 0,
                       "the same for the shapes that keep the title bar")

        pane.setMinimized(to: nil)
        XCTAssertEqual(try activeContentPins(of: pane), 4,
                       "and they are back before the content is visible again")
    }

    /// `setMinimized` can arrive before the pane has ever been shown — a host
    /// re-applying a remembered layout to a tab nobody has opened. Touching
    /// `view` there loads it, and `viewDidLoad` re-enters the same method
    /// through `restorePersistedState()`: the inner call builds the rail
    /// `minimizedStrip` keeps, and the outer call adds a second one that
    /// nothing tracks and no restore can remove.
    func testMinimizingBeforeTheViewLoadsLeavesOneRailNotTwo() {
        let pane = TestPane(content: RichContent())
        pane.setMinimized(to: .leading)
        XCTAssertFalse(pane.isViewLoaded, "asking for the appearance must not build the view")

        pane.loadViewIfNeeded()
        let strips = pane.view.subviews.compactMap { $0 as? PaneMinimizedStripView }
        XCTAssertEqual(strips.count, 1)
        XCTAssertEqual(pane.minimizedEdge, .leading, "and the edge survived the deferral")
        XCTAssertTrue(pane.titleBar.isHidden)

        // The one rail that exists is the one the pane can still take away.
        pane.setMinimized(to: nil)
        XCTAssertTrue(pane.view.subviews.compactMap { $0 as? PaneMinimizedStripView }.isEmpty)
    }

    // MARK: - Persistence

    func testMinimizeAndZoomAreWrittenThroughTheStore() {
        let store = EphemeralPaneStateStore()
        let (pane, _) = loadedPane(content: BareContent(), store: store)

        pane.setMinimized(to: .bottom)
        XCTAssertEqual(store.paneStateValue(forKey: PaneStateKey.minimizeEdge), "bottom")

        pane.setZoomed(true)
        XCTAssertEqual(store.paneStateValue(forKey: PaneStateKey.zoomed), "1")
    }

    /// Restoring deletes rather than writing a "no" — see `PaneStateStore`.
    func testRestoringAndUnzoomingDeleteTheirKeys() {
        let store = EphemeralPaneStateStore()
        let (pane, _) = loadedPane(content: BareContent(), store: store)
        pane.setMinimized(to: .bottom)
        pane.setZoomed(true)

        pane.setMinimized(to: nil)
        pane.setZoomed(false)
        XCTAssertNil(store.paneStateValue(forKey: PaneStateKey.minimizeEdge))
        XCTAssertNil(store.paneStateValue(forKey: PaneStateKey.zoomed))
    }

    /// The pane restores its own *appearance* from the store as it loads. What
    /// the surrounding tree has to do about it is the host's to read back off
    /// `persistedMinimizeEdge` / `persistedZoomed`.
    func testAPaneLoadsBackIntoTheStateItWasSavedIn() {
        let store = EphemeralPaneStateStore()
        store.setPaneStateValue("trailing", forKey: PaneStateKey.minimizeEdge)
        store.setPaneStateValue("1", forKey: PaneStateKey.zoomed)

        let (pane, _) = loadedPane(content: RichContent(), store: store)
        XCTAssertEqual(pane.persistedMinimizeEdge, .trailing)
        XCTAssertTrue(pane.persistedZoomed)
        XCTAssertEqual(pane.minimizedEdge, .trailing)
        XCTAssertTrue(pane.isZoomed)
    }

    func testAnUnreadableStoredEdgeIsIgnoredRatherThanCrashing() {
        let store = EphemeralPaneStateStore()
        store.setPaneStateValue("sideways", forKey: PaneStateKey.minimizeEdge)
        let (pane, _) = loadedPane(content: BareContent(), store: store)
        XCTAssertNil(pane.persistedMinimizeEdge)
        XCTAssertNil(pane.minimizedEdge)
    }

    // MARK: - Search and selection

    func testSearchReachesSearchableContentOnly() {
        let content = RichContent()
        let (pane, _) = loadedPane(content: content)
        XCTAssertTrue(pane.isSearchable)
        XCTAssertEqual(pane.searchPlaceholder, "Filter files")
        pane.search(for: "main")
        XCTAssertEqual(content.receivedQueries, ["main"])

        let (bare, _) = loadedPane(content: BareContent())
        XCTAssertFalse(bare.isSearchable)
        XCTAssertNil(bare.searchPlaceholder)
        bare.search(for: "main")  // a no-op, not a crash
    }

    func testSelectionIsReportedAndItsChangesAreForwarded() {
        let content = RichContent()
        let (pane, _) = loadedPane(content: content)
        var notifications = 0
        pane.onSelectionChange = { notifications += 1 }

        XCTAssertEqual(pane.selectionDescription, "src/main.swift")
        content.paneSelectionDescription = "README.md"
        XCTAssertEqual(pane.selectionDescription, "README.md")
        XCTAssertEqual(notifications, 1)
    }

    func testBareContentDescribesNoSelection() {
        let (pane, _) = loadedPane(content: BareContent())
        XCTAssertNil(pane.selectionDescription)
    }
}
