import AppKit
import XCTest
@testable import AgenticToolkitMacOS

/// A pane's content contributes upward through six protocols it opts into one
/// at a time. These tests pin the two halves of that: content implementing none
/// of them fails every probe (which is what makes the fallbacks reachable), and
/// content implementing all six answers every one.
@MainActor
final class PaneCapabilitiesTests: XCTestCase {

    /// Content that opts into nothing. Every fallback in `PaneViewController`
    /// exists for this object.
    private final class BareContent: NSViewController {}

    /// Content that opts into everything, so each surface can be proven to be
    /// driven by the protocol rather than by a coincidence.
    private final class FullContent: NSViewController,
        PaneTitleProviding, PaneAccessoryProviding, PaneOptionsProviding,
        PaneMinimizedRepresenting, PaneSearchable, PaneSelectionDescribing {

        var paneTitle = "Files"
        var onPaneTitleChange: (() -> Void)?
        var paneSelectionDescription: String? = "src/main.swift"
        var onPaneSelectionChange: (() -> Void)?
        var paneSearchPlaceholder = "Filter files"
        private(set) var receivedQueries: [String] = []

        func makePaneAccessoryViews() -> [NSView] { [NSButton()] }
        func makePaneOptionRows() -> [NSView] { [NSButton(), NSButton()] }
        var paneMinimizedSymbolName: String { "folder" }
        var paneMinimizedTooltip: String { "Files" }
        func paneSearch(for query: String) { receivedQueries.append(query) }
    }

    func testContentImplementingNothingFailsEveryProbe() {
        let content: NSViewController = BareContent()
        XCTAssertNil(content as? PaneTitleProviding)
        XCTAssertNil(content as? PaneAccessoryProviding)
        XCTAssertNil(content as? PaneOptionsProviding)
        XCTAssertNil(content as? PaneMinimizedRepresenting)
        XCTAssertNil(content as? PaneSearchable)
        XCTAssertNil(content as? PaneSelectionDescribing)
    }

    func testContentImplementingEverythingAnswersEveryProbe() {
        let content: NSViewController = FullContent()
        XCTAssertEqual((content as? PaneTitleProviding)?.paneTitle, "Files")
        XCTAssertEqual((content as? PaneAccessoryProviding)?.makePaneAccessoryViews().count, 1)
        XCTAssertEqual((content as? PaneOptionsProviding)?.makePaneOptionRows().count, 2)
        XCTAssertEqual((content as? PaneMinimizedRepresenting)?.paneMinimizedSymbolName, "folder")
        XCTAssertEqual((content as? PaneSearchable)?.paneSearchPlaceholder, "Filter files")
        XCTAssertEqual((content as? PaneSelectionDescribing)?.paneSelectionDescription, "src/main.swift")
    }

    /// The reason the protocols are class-bound: a pane installs its own
    /// closure into the content's callback, and that assignment only compiles
    /// through a class-bound existential.
    func testChangeCallbacksAreInstallableThroughTheExistential() {
        let content: NSViewController = FullContent()
        var titleChanges = 0
        var selectionChanges = 0
        (content as? PaneTitleProviding)?.onPaneTitleChange = { titleChanges += 1 }
        (content as? PaneSelectionDescribing)?.onPaneSelectionChange = { selectionChanges += 1 }

        (content as? PaneTitleProviding)?.onPaneTitleChange?()
        (content as? PaneSelectionDescribing)?.onPaneSelectionChange?()

        XCTAssertEqual(titleChanges, 1)
        XCTAssertEqual(selectionChanges, 1)
    }

    func testSearchQueriesReachTheContent() {
        let content = FullContent()
        (content as PaneSearchable).paneSearch(for: "main")
        XCTAssertEqual(content.receivedQueries, ["main"])
    }

    // MARK: - The state store

    func testEphemeralStoreRoundTripsAndForgetsOnNil() {
        let store = EphemeralPaneStateStore()
        XCTAssertNil(store.paneStateValue(forKey: PaneStateKey.zoomed))

        store.setPaneStateValue("1", forKey: PaneStateKey.zoomed)
        XCTAssertEqual(store.paneStateValue(forKey: PaneStateKey.zoomed), "1")

        store.setPaneStateValue(nil, forKey: PaneStateKey.zoomed)
        XCTAssertNil(store.paneStateValue(forKey: PaneStateKey.zoomed),
                     "writing nil deletes the key rather than storing an empty string")
    }

    /// The keys are what a `pane_state` row is named by, so they are storage
    /// contract: renaming one orphans everything already saved under it.
    func testStateKeysAreTheStringsAlreadyOnDisk() {
        XCTAssertEqual(PaneStateKey.minimizeEdge, "minimize.edge")
        XCTAssertEqual(PaneStateKey.zoomed, "zoomed")
        XCTAssertEqual(PaneStateKey.spacingOverride, "spacing.override")
    }
}
