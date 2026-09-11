import AppKit
import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class PaneSpacingOverrideTests: XCTestCase {

    private func makeOverride(
        store: PaneStateStore = EphemeralPaneStateStore(),
        inherited: Spacing = Spacing(top: 10, leading: 10, bottom: 10, trailing: 10)
    ) -> PaneSpacingOverride {
        PaneSpacingOverride(store: store, inherited: { inherited })
    }

    // MARK: - The model

    func testAPaneWithNoRowInheritsTheGlobal() {
        let override = makeOverride()
        XCTAssertFalse(override.isOverridden)
        XCTAssertEqual(override.resolved, Spacing(top: 10, leading: 10, bottom: 10, trailing: 10))
    }

    func testAnOverrideWinsOverTheGlobal() {
        let override = makeOverride()
        override.setOverride(Spacing(top: 4, leading: 0, bottom: 4, trailing: 0))

        XCTAssertTrue(override.isOverridden)
        XCTAssertEqual(override.resolved, Spacing(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    /// Zero on every side is a *look*, not an absence of an opinion — which is
    /// why "use default" is its own button rather than the reset the control
    /// already has.
    func testAnAllZeroOverrideIsStillAnOverride() {
        let override = makeOverride()
        override.setOverride(Spacing())
        XCTAssertTrue(override.isOverridden)
        XCTAssertEqual(override.resolved, Spacing())
    }

    func testResettingGoesBackToInheritingRatherThanFreezingTodaysGlobal() {
        let store = EphemeralPaneStateStore()
        let override = makeOverride(store: store)
        override.setOverride(Spacing(uniform: 3))
        override.reset()

        XCTAssertFalse(override.isOverridden)
        XCTAssertNil(store.paneStateValue(forKey: PaneStateKey.spacingOverride),
                     "the row is deleted, so a later change to the global still reaches the pane")
        XCTAssertEqual(override.resolved, Spacing(top: 10, leading: 10, bottom: 10, trailing: 10))
    }

    func testTheOverrideRoundTripsThroughTheStore() {
        let store = EphemeralPaneStateStore()
        let override = makeOverride(store: store)
        override.setOverride(Spacing(top: 1, leading: 2, bottom: 3, trailing: 4))
        // The write is coalesced, so the row is not there until the pause the
        // gesture never takes here has passed. Flushing is what a caller about
        // to read the store back through a second override does.
        override.flushPendingPersist()

        let reloaded = makeOverride(store: store)
        XCTAssertTrue(reloaded.isOverridden)
        XCTAssertEqual(reloaded.resolved, Spacing(top: 1, leading: 2, bottom: 3, trailing: 4))
    }

    /// Only the four edges are stored. The two gutters belong to the grid, not
    /// to one pane, so a `.frame` control never edits them and they must not
    /// come back as anything but zero.
    func testGuttersAreNotPartOfAPanesOverride() {
        let store = EphemeralPaneStateStore()
        let override = makeOverride(store: store)
        override.setOverride(
            Spacing(top: 1, leading: 1, bottom: 1, trailing: 1, betweenColumns: 9, betweenRows: 9)
        )
        override.flushPendingPersist()
        XCTAssertEqual(makeOverride(store: store).resolved.betweenColumns, 0)
        XCTAssertEqual(makeOverride(store: store).resolved.betweenRows, 0)
    }

    func testAnUnreadableRowIsIgnoredRatherThanCrashing() {
        let store = EphemeralPaneStateStore()
        store.setPaneStateValue("{ not json", forKey: PaneStateKey.spacingOverride)
        let override = makeOverride(store: store)
        XCTAssertFalse(override.isOverridden)
        XCTAssertEqual(override.resolved, Spacing(top: 10, leading: 10, bottom: 10, trailing: 10))
    }

    /// A row that parses but says something the control could never have
    /// produced. `setOverride` clamps on the way in, so the only sources are an
    /// older build or a hand-edited database — the same sources the unreadable
    /// row above comes from — and honouring the number would put the pane in a
    /// state its own slider cannot show or walk back from.
    func testAnOutOfRangeRowIsClampedRatherThanHonoured() {
        let store = EphemeralPaneStateStore()
        store.setPaneStateValue(
            #"{"top":999,"leading":-4,"bottom":40,"trailing":0}"#,
            forKey: PaneStateKey.spacingOverride)

        let override = makeOverride(store: store)

        XCTAssertTrue(override.isOverridden)
        XCTAssertEqual(
            override.resolved,
            Spacing(top: PaneSpacingOverride.range.upperBound,
                    leading: PaneSpacingOverride.range.lowerBound,
                    bottom: 40,
                    trailing: 0))
    }

    func testChangesAreAnnouncedOnceEach() {
        let override = makeOverride()
        var announced: [Spacing] = []
        override.onChange = { announced.append($0) }

        override.setOverride(Spacing(uniform: 2))
        override.reset()

        // `setOverride` stores only the four edges (`testGuttersAreNotPartOfAPanesOverride`),
        // so the announced value never carries the gutters `Spacing(uniform:)` also sets —
        // it is the edge-only spacing that comes back out, not the literal input.
        XCTAssertEqual(announced, [Spacing(top: 2, leading: 2, bottom: 2, trailing: 2),
                                   Spacing(top: 10, leading: 10, bottom: 10, trailing: 10)])
    }

    func testInsetsAreTheResolvedValueInAppKitsShape() {
        let override = makeOverride()
        override.setOverride(Spacing(top: 1, leading: 2, bottom: 3, trailing: 4))
        XCTAssertEqual(override.insets.top, 1)
        XCTAssertEqual(override.insets.left, 2)
        XCTAssertEqual(override.insets.bottom, 3)
        XCTAssertEqual(override.insets.right, 4)
    }

    // MARK: - Coalescing the write

    /// The steppers are continuous, so a held arrow key used to produce a JSON
    /// encode plus a synchronous write per tick. Every tick still changes the
    /// value the pane draws with — only the row waits.
    func testAGestureIsOneWriteRatherThanOnePerTick() {
        let store = CountingPaneStateStore()
        let override = makeOverride(store: store)

        for edge in 1...8 { override.setOverride(Spacing(uniform: edge)) }

        XCTAssertEqual(store.writes, 0, "nothing is on disk while the gesture is still running")
        XCTAssertEqual(override.resolved, Spacing(top: 8, leading: 8, bottom: 8, trailing: 8),
                       "the value the pane draws with is never the one that waits")

        override.flushPendingPersist()

        XCTAssertEqual(store.writes, 1, "eight ticks, one row")
        XCTAssertEqual(makeOverride(store: store).resolved,
                       Spacing(top: 8, leading: 8, bottom: 8, trailing: 8),
                       "and the row that lands is the last value, not the first")
    }

    /// The failure this ordering exists to prevent: a queued write from the
    /// gesture just before a reset landing *after* the deletion and putting the
    /// override straight back.
    func testResettingCancelsAWriteTheGestureBeforeItEarned() {
        let store = CountingPaneStateStore()
        let override = makeOverride(store: store)

        override.setOverride(Spacing(uniform: 5))
        override.reset()
        override.flushPendingPersist()

        XCTAssertFalse(override.isOverridden)
        XCTAssertNil(store.paneStateValue(forKey: PaneStateKey.spacingOverride))
    }

    /// Flushing with nothing pending must not write — otherwise a caller that
    /// flushes defensively would re-create a row `reset()` just deleted.
    func testFlushingWithNothingPendingWritesNothing() {
        let store = CountingPaneStateStore()
        let override = makeOverride(store: store)

        override.flushPendingPersist()
        override.setOverride(Spacing(uniform: 2))
        override.flushPendingPersist()
        override.flushPendingPersist()

        XCTAssertEqual(store.writes, 1)
    }

    /// Counts what reaches the store, so "one gesture, one write" is an
    /// assertion rather than a claim in a comment.
    @MainActor
    private final class CountingPaneStateStore: PaneStateStore {
        private let backing = EphemeralPaneStateStore()
        private(set) var writes = 0

        func paneStateValue(forKey key: String) -> String? {
            backing.paneStateValue(forKey: key)
        }

        func setPaneStateValue(_ value: String?, forKey key: String) {
            if value != nil { writes += 1 }
            backing.setPaneStateValue(value, forKey: key)
        }
    }

    // MARK: - The pane

    private final class SpacingAwareContent: NSViewController, PaneContentSpacingConsuming {
        let inheritedPaneSpacing = Spacing(uniform: 10)
        private(set) var applied: [Spacing] = []
        func applyPaneSpacing(_ spacing: Spacing) { applied.append(spacing) }
    }

    private final class PlainContent: NSViewController {}

    private final class TestPane: PaneViewController {
        let content: NSViewController
        let inherited: Spacing
        init(content: NSViewController,
             inherited: Spacing = Spacing(uniform: 10),
             stateStore: PaneStateStore = EphemeralPaneStateStore()) {
            self.content = content
            self.inherited = inherited
            super.init(stateStore: stateStore)
        }
        override func makeContentViewController() -> NSViewController? { content }
        override var inheritedPaneSpacing: Spacing { inherited }
    }

    func testTheGearLeadsWithTheSpacingControlThenTheContentsOwnRows() {
        let pane = TestPane(content: PlainContent())
        pane.loadViewIfNeeded()

        let rows = pane.makeOptionRows()
        XCTAssertTrue(rows.first is SpacingControl)
        XCTAssertEqual((rows.first as? SpacingControl)?.style, .frame)
        XCTAssertTrue(rows.dropFirst().first?.accessibilityIdentifier()
                      == "pane.options.spacing.reset")
    }

    func testTheControlStartsAtWhatThePaneInherits() {
        let pane = TestPane(content: PlainContent(), inherited: Spacing(uniform: 7))
        pane.loadViewIfNeeded()

        let control = pane.makeOptionRows().first as? SpacingControl
        XCTAssertEqual(control?.value, Spacing(uniform: 7))
    }

    func testMovingTheControlWritesAnOverrideAndTheResetButtonWakesUp() {
        let pane = TestPane(content: PlainContent())
        pane.loadViewIfNeeded()

        let rows = pane.makeOptionRows()
        let control = rows.first as? SpacingControl
        let reset = rows.dropFirst().first as? NSButton
        XCTAssertEqual(reset?.isEnabled, false, "nothing to go back to while inheriting")

        control?.onChange?(Spacing(uniform: 2))
        XCTAssertTrue(pane.spacingOverride.isOverridden)
        XCTAssertEqual(reset?.isEnabled, true)
    }

    func testPressingUseDefaultReturnsThePaneToInheriting() {
        let pane = TestPane(content: PlainContent(), inherited: Spacing(uniform: 10))
        pane.loadViewIfNeeded()

        let rows = pane.makeOptionRows()
        let control = rows.first as? SpacingControl
        let reset = rows.dropFirst().first as? NSButton
        control?.onChange?(Spacing(uniform: 2))
        reset?.performClick(nil)

        XCTAssertFalse(pane.spacingOverride.isOverridden)
        XCTAssertEqual(control?.value, Spacing(uniform: 10), "the picture follows the value back")
    }

    /// The coalescing is only safe because something ends the gesture. The
    /// steppers live in the options dialog and nowhere else, so the dialog
    /// closing is that moment — and closing the window closes it too.
    func testDismissingTheOptionsDialogWritesWhatTheGestureLeftWaiting() {
        let store = CountingPaneStateStore()
        let pane = TestPane(content: PlainContent(), stateStore: store)
        pane.loadViewIfNeeded()
        let control = pane.makeOptionRows().first as? SpacingControl

        control?.onChange?(Spacing(uniform: 2))
        XCTAssertEqual(store.writes, 0, "still mid-gesture")

        pane.optionsDialogDidClose()

        XCTAssertEqual(store.writes, 1)
        XCTAssertNotNil(store.paneStateValue(forKey: PaneStateKey.spacingOverride))
    }

    /// The rule this task exists for, in both directions.
    func testContentThatAppliesItsOwnPaddingIsHandedTheValueAndPinnedFlush() {
        let content = SpacingAwareContent()
        let pane = TestPane(content: content, inherited: Spacing(uniform: 10))
        pane.loadViewIfNeeded()

        XCTAssertEqual(content.applied.last, Spacing(uniform: 10))
        XCTAssertEqual(pane.contentSpacingInsets, NSEdgeInsets(),
                       "the pane must not add the same gap a second time")
    }

    func testContentThatDoesNotHasTheGapAppliedForIt() {
        let pane = TestPane(content: PlainContent(), inherited: Spacing(uniform: 10))
        pane.loadViewIfNeeded()

        XCTAssertEqual(pane.contentSpacingInsets.top, 10)
        XCTAssertEqual(pane.contentSpacingInsets.left, 10)
    }

    /// A pane that overrides nothing still inherits the right number, because
    /// the content that applies the gap is the thing that names it.
    func testAPaneWithNoOpinionInheritsWhatItsContentApplies() {
        final class DefaultingPane: PaneViewController {
            let content: NSViewController
            init(content: NSViewController) {
                self.content = content
                super.init(stateStore: EphemeralPaneStateStore())
            }
            override func makeContentViewController() -> NSViewController? { content }
        }

        let pane = DefaultingPane(content: SpacingAwareContent())
        pane.loadViewIfNeeded()
        XCTAssertEqual(pane.spacingOverride.resolved, Spacing(uniform: 10))
    }

    /// `applyResolvedSpacing` assigns, it never adds. It runs once per override
    /// change already, so calling it again must leave the gap at the number the
    /// override names rather than doubling it (`idempotency`).
    func testApplyingTheSpacingRepeatedlyDoesNotAccumulate() {
        let pane = TestPane(content: PlainContent(), inherited: Spacing(uniform: 10))
        pane.loadViewIfNeeded()

        pane.spacingOverride.setOverride(Spacing(uniform: 4))
        pane.applyResolvedSpacing()
        pane.applyResolvedSpacing()

        XCTAssertEqual(pane.contentSpacingInsets.top, 4)
        XCTAssertEqual(pane.contentSpacingInsets.left, 4)
        XCTAssertEqual(pane.contentSpacingInsets.bottom, 4)
        XCTAssertEqual(pane.contentSpacingInsets.right, 4)

        pane.spacingOverride.setOverride(Spacing(uniform: 6))
        pane.applyResolvedSpacing()

        XCTAssertEqual(pane.contentSpacingInsets.top, 6,
                       "a second change replaces the first rather than adding to it")
        XCTAssertEqual(pane.contentSpacingInsets.left, 6)
    }

    /// The same guarantee on the other branch: content that applies its own
    /// padding keeps the pane flush at zero however often the pane is asked.
    func testRepeatedApplicationLeavesSpacingAwareContentFlush() {
        let content = SpacingAwareContent()
        let pane = TestPane(content: content, inherited: Spacing(uniform: 10))
        pane.loadViewIfNeeded()

        pane.spacingOverride.setOverride(Spacing(uniform: 3))
        pane.applyResolvedSpacing()

        XCTAssertEqual(content.applied.last, Spacing(top: 3, leading: 3, bottom: 3, trailing: 3))
        XCTAssertEqual(pane.contentSpacingInsets, NSEdgeInsets(),
                       "the pane adds nothing on top, no matter how many times it is called")
    }

    func testAnOverrideReachesSpacingAwareContentImmediately() {
        let content = SpacingAwareContent()
        let pane = TestPane(content: content)
        pane.loadViewIfNeeded()

        pane.spacingOverride.setOverride(Spacing(uniform: 1))
        // Same reason as `testChangesAreAnnouncedOnceEach`: the stored override
        // drops the gutters, so the value applied to content is edge-only.
        XCTAssertEqual(content.applied.last, Spacing(top: 1, leading: 1, bottom: 1, trailing: 1))
    }
}
