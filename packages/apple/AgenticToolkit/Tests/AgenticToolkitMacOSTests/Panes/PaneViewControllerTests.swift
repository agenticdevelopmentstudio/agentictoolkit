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

        func makePaneAccessoryViews() -> [NSView] { [accessory] }
        func makePaneOptionRows() -> [NSView] { [NSButton(), NSButton()] }
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
        XCTAssertEqual(pane.makeOptionRows().count, 2)
    }

    func testBareContentGetsNoAccessoriesAndNoOptionRows() {
        let (pane, _) = loadedPane(content: BareContent())
        XCTAssertTrue(pane.titleBar.accessoryViews.isEmpty)
        XCTAssertTrue(pane.makeOptionRows().isEmpty)
    }

    func testTheGearIsInTheTitleBarsTrailingSlot() {
        let (pane, _) = loadedPane(content: BareContent())
        XCTAssertNotNil(pane.titleBar.gearView)
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
