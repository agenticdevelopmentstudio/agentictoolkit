import XCTest
@testable import AgenticToolkitMacOS

final class FrameCalculatorTests: XCTestCase {

    // MARK: - Proportional Position

    func testProportionalPositionCenter() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = NSRect(x: 760, y: 340, width: 400, height: 400)
        let pos = FrameCalculator.proportionalPosition(windowFrame: window, screenVisibleFrame: screen)
        XCTAssertEqual(pos.x, 0.5, accuracy: 0.01)
        XCTAssertEqual(pos.y, 0.5, accuracy: 0.01)
    }

    func testProportionalPositionTopRight() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = NSRect(x: 1520, y: 680, width: 400, height: 400)
        let pos = FrameCalculator.proportionalPosition(windowFrame: window, screenVisibleFrame: screen)
        XCTAssertEqual(pos.x, 1.0, accuracy: 0.01)
        XCTAssertEqual(pos.y, 1.0, accuracy: 0.01)
    }

    func testProportionalPositionBottomLeft() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = NSRect(x: 0, y: 0, width: 400, height: 400)
        let pos = FrameCalculator.proportionalPosition(windowFrame: window, screenVisibleFrame: screen)
        XCTAssertEqual(pos.x, 0.0, accuracy: 0.01)
        XCTAssertEqual(pos.y, 0.0, accuracy: 0.01)
    }

    func testProportionalPositionWindowFillsScreen() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let pos = FrameCalculator.proportionalPosition(windowFrame: window, screenVisibleFrame: screen)
        XCTAssertEqual(pos.x, 0.5)
        XCTAssertEqual(pos.y, 0.5)
    }

    // MARK: - Absolute Frame

    func testAbsoluteFrameCenter() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = FrameCalculator.absoluteFrame(
            proportionalX: 0.5, proportionalY: 0.5,
            width: 600, height: 480,
            screenVisibleFrame: screen,
            minSize: NSSize(width: 100, height: 100)
        )
        XCTAssertEqual(frame.origin.x, 660, accuracy: 1)
        XCTAssertEqual(frame.origin.y, 300, accuracy: 1)
        XCTAssertEqual(frame.width, 600)
        XCTAssertEqual(frame.height, 480)
    }

    func testAbsoluteFrameTopRight() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = FrameCalculator.absoluteFrame(
            proportionalX: 1.0, proportionalY: 1.0,
            width: 400, height: 300,
            screenVisibleFrame: screen,
            minSize: NSSize(width: 100, height: 100)
        )
        XCTAssertEqual(frame.origin.x, 1520, accuracy: 1)
        XCTAssertEqual(frame.origin.y, 780, accuracy: 1)
    }

    func testAbsoluteFrameClampsToMinSize() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = FrameCalculator.absoluteFrame(
            proportionalX: 0.5, proportionalY: 0.5,
            width: 50, height: 50,
            screenVisibleFrame: screen,
            minSize: NSSize(width: 200, height: 200)
        )
        XCTAssertEqual(frame.width, 200)
        XCTAssertEqual(frame.height, 200)
    }

    func testAbsoluteFrameClampsToScreenSize() {
        let screen = NSRect(x: 0, y: 0, width: 800, height: 600)
        let frame = FrameCalculator.absoluteFrame(
            proportionalX: 0.5, proportionalY: 0.5,
            width: 1200, height: 900,
            screenVisibleFrame: screen,
            minSize: NSSize(width: 100, height: 100)
        )
        XCTAssertEqual(frame.width, 800)
        XCTAssertEqual(frame.height, 600)
    }

    func testAbsoluteFrameWithScreenOffset() {
        let screen = NSRect(x: 1920, y: 0, width: 1920, height: 1080)
        let frame = FrameCalculator.absoluteFrame(
            proportionalX: 0.5, proportionalY: 0.5,
            width: 600, height: 480,
            screenVisibleFrame: screen,
            minSize: NSSize(width: 100, height: 100)
        )
        XCTAssertEqual(frame.origin.x, 1920 + 660, accuracy: 1)
    }

    // MARK: - Roundtrip

    func testProportionalRoundtrip() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let originalFrame = NSRect(x: 300, y: 200, width: 600, height: 480)

        let pos = FrameCalculator.proportionalPosition(windowFrame: originalFrame, screenVisibleFrame: screen)
        let restored = FrameCalculator.absoluteFrame(
            proportionalX: pos.x, proportionalY: pos.y,
            width: originalFrame.width, height: originalFrame.height,
            screenVisibleFrame: screen,
            minSize: NSSize(width: 100, height: 100)
        )

        XCTAssertEqual(restored.origin.x, originalFrame.origin.x, accuracy: 1)
        XCTAssertEqual(restored.origin.y, originalFrame.origin.y, accuracy: 1)
        XCTAssertEqual(restored.width, originalFrame.width)
        XCTAssertEqual(restored.height, originalFrame.height)
    }

    func testProportionalRoundtripOnSecondaryScreen() {
        let screen = NSRect(x: 1920, y: -200, width: 2560, height: 1440)
        let originalFrame = NSRect(x: 3800, y: 800, width: 500, height: 400)

        let pos = FrameCalculator.proportionalPosition(windowFrame: originalFrame, screenVisibleFrame: screen)
        let restored = FrameCalculator.absoluteFrame(
            proportionalX: pos.x, proportionalY: pos.y,
            width: originalFrame.width, height: originalFrame.height,
            screenVisibleFrame: screen,
            minSize: NSSize(width: 100, height: 100)
        )

        XCTAssertEqual(restored.origin.x, originalFrame.origin.x, accuracy: 1)
        XCTAssertEqual(restored.origin.y, originalFrame.origin.y, accuracy: 1)
    }

    // MARK: - Frame Validation

    func testValidateFrameFullyOnScreen() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = NSRect(x: 100, y: 100, width: 400, height: 300)
        let result = FrameCalculator.validateFrame(
            frame,
            screenVisibleFrame: screen,
            minSize: NSSize(width: 100, height: 100)
        )
        XCTAssertEqual(result, frame)
    }

    func testValidateFramePushesFromRight() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = NSRect(x: 1800, y: 100, width: 400, height: 300)
        let result = FrameCalculator.validateFrame(
            frame,
            screenVisibleFrame: screen,
            minSize: NSSize(width: 100, height: 100)
        )
        XCTAssertEqual(result.maxX, 1920, accuracy: 1)
        XCTAssertEqual(result.width, 400)
    }

    func testValidateFramePushesFromTop() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = NSRect(x: 100, y: 900, width: 400, height: 300)
        let result = FrameCalculator.validateFrame(
            frame,
            screenVisibleFrame: screen,
            minSize: NSSize(width: 100, height: 100)
        )
        XCTAssertEqual(result.maxY, 1080, accuracy: 1)
    }

    func testValidateFramePushesFromLeft() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = NSRect(x: -100, y: 100, width: 400, height: 300)
        let result = FrameCalculator.validateFrame(
            frame,
            screenVisibleFrame: screen,
            minSize: NSSize(width: 100, height: 100)
        )
        XCTAssertEqual(result.origin.x, 0)
    }

    func testValidateFramePushesFromBottom() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = NSRect(x: 100, y: -50, width: 400, height: 300)
        let result = FrameCalculator.validateFrame(
            frame,
            screenVisibleFrame: screen,
            minSize: NSSize(width: 100, height: 100)
        )
        XCTAssertEqual(result.origin.y, 0)
    }

    func testValidateFrameEnforcesMinSize() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = NSRect(x: 100, y: 100, width: 50, height: 30)
        let result = FrameCalculator.validateFrame(
            frame,
            screenVisibleFrame: screen,
            minSize: NSSize(width: 200, height: 150)
        )
        XCTAssertEqual(result.width, 200)
        XCTAssertEqual(result.height, 150)
    }

    func testValidateFrameClampsOversizeToScreen() {
        let screen = NSRect(x: 0, y: 0, width: 800, height: 600)
        let frame = NSRect(x: 0, y: 0, width: 1200, height: 900)
        let result = FrameCalculator.validateFrame(
            frame,
            screenVisibleFrame: screen,
            minSize: NSSize(width: 100, height: 100)
        )
        XCTAssertEqual(result.width, 800)
        XCTAssertEqual(result.height, 600)
    }

    func testValidateFrameWithMenuBarOffset() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1055)
        let frame = NSRect(x: 100, y: 900, width: 400, height: 300)
        let result = FrameCalculator.validateFrame(
            frame,
            screenVisibleFrame: screen,
            minSize: NSSize(width: 100, height: 100)
        )
        XCTAssertLessThanOrEqual(result.maxY, 1055)
    }

    // MARK: - Default Frame

    func testDefaultFrameCenter() {
        let spec = WindowSpec(
            defaultSize: NSSize(width: 600, height: 480),
            minSize: NSSize(width: 100, height: 100),
            defaultPosition: .center,
            persistsFrame: true
        )
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = FrameCalculator.defaultFrame(spec: spec, screenVisibleFrame: screen)
        XCTAssertEqual(frame.origin.x, 660, accuracy: 1)
        XCTAssertEqual(frame.origin.y, 300, accuracy: 1)
    }

    func testDefaultFrameTopRight() {
        let spec = WindowSpec(
            defaultSize: NSSize(width: 340, height: 300),
            minSize: NSSize(width: 280, height: 120),
            defaultPosition: .topRight,
            persistsFrame: true
        )
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = FrameCalculator.defaultFrame(spec: spec, screenVisibleFrame: screen)
        XCTAssertEqual(frame.origin.x, 1342, accuracy: 1)
        XCTAssertEqual(frame.origin.y, 663, accuracy: 1)
    }

    // MARK: - Top-left offset (user-POV: y grows downward)

    func testTopLeftOffsetAtScreenTopLeftIsZero() {
        // Menu-bar inset screen: visible top is y=1055 in macOS coords.
        let visible = NSRect(x: 0, y: 0, width: 1920, height: 1055)
        let window = NSRect(x: 0, y: 1055 - 300, width: 500, height: 300)
        let offset = FrameCalculator.topLeftOffset(windowFrame: window, screenVisibleFrame: visible)
        XCTAssertEqual(offset.x, 0)
        XCTAssertEqual(offset.y, 0)
    }

    func testTopLeftOffsetMeasuresDownFromVisibleTop() {
        let visible = NSRect(x: 100, y: 50, width: 1920, height: 1000)
        // Window top-left 60pt right of and 40pt below the visible top-left.
        let window = NSRect(x: 160, y: 50 + 1000 - 40 - 300, width: 500, height: 300)
        let offset = FrameCalculator.topLeftOffset(windowFrame: window, screenVisibleFrame: visible)
        XCTAssertEqual(offset.x, 60)
        XCTAssertEqual(offset.y, 40)
    }

    func testTopLeftOffsetRoundTrip() {
        let visible = NSRect(x: -800, y: 200, width: 2560, height: 1400)
        let original = NSRect(x: -300, y: 700, width: 640, height: 420)
        let offset = FrameCalculator.topLeftOffset(windowFrame: original, screenVisibleFrame: visible)
        let rebuilt = FrameCalculator.frame(
            topLeftOffset: offset, size: original.size, screenVisibleFrame: visible
        )
        XCTAssertEqual(rebuilt, original)
    }

    func testTopLeftAnchorSurvivesHeightChange() {
        // The drift bug's root: growing height with a fixed top edge must
        // not change the persisted anchor.
        let visible = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let short = NSRect(x: 250, y: 800 - 260, width: 500, height: 260)
        let tall = NSRect(x: 250, y: 800 - 420, width: 500, height: 420)
        XCTAssertEqual(
            FrameCalculator.topLeftOffset(windowFrame: short, screenVisibleFrame: visible),
            FrameCalculator.topLeftOffset(windowFrame: tall, screenVisibleFrame: visible)
        )
    }

    // MARK: - Relative position (0,0 = top-left … 1,1 = bottom-right)

    func testRelativePositionCorners() {
        let visible = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let size = NSSize(width: 600, height: 480)

        let topLeft = NSRect(x: 0, y: 1080 - 480, width: 600, height: 480)
        XCTAssertEqual(
            FrameCalculator.relativePosition(windowFrame: topLeft, screenVisibleFrame: visible),
            CGPoint(x: 0, y: 0)
        )

        let bottomRight = NSRect(x: 1920 - 600, y: 0, width: size.width, height: size.height)
        XCTAssertEqual(
            FrameCalculator.relativePosition(windowFrame: bottomRight, screenVisibleFrame: visible),
            CGPoint(x: 1, y: 1)
        )

        let bottomLeft = NSRect(x: 0, y: 0, width: 600, height: 480)
        XCTAssertEqual(
            FrameCalculator.relativePosition(windowFrame: bottomLeft, screenVisibleFrame: visible),
            CGPoint(x: 0, y: 1)
        )

        let centered = NSRect(x: 660, y: 300, width: 600, height: 480)
        XCTAssertEqual(
            FrameCalculator.relativePosition(windowFrame: centered, screenVisibleFrame: visible),
            CGPoint(x: 0.5, y: 0.5)
        )
    }

    func testRelativePositionClampsOffscreenTo0And1() {
        let visible = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let hangingOff = NSRect(x: -200, y: -300, width: 600, height: 480)
        let position = FrameCalculator.relativePosition(windowFrame: hangingOff, screenVisibleFrame: visible)
        XCTAssertEqual(position.x, 0)
        XCTAssertEqual(position.y, 1)
    }

    func testRelativePositionCenteredWhenNoTravel() {
        let visible = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let fullSize = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let position = FrameCalculator.relativePosition(windowFrame: fullSize, screenVisibleFrame: visible)
        XCTAssertEqual(position, CGPoint(x: 0.5, y: 0.5))
    }

    func testFrameFromRelativePositionRoundTrip() {
        let visible = NSRect(x: 100, y: 70, width: 1920, height: 985)
        let original = NSRect(x: 500, y: 300, width: 640, height: 400)
        let relative = FrameCalculator.relativePosition(windowFrame: original, screenVisibleFrame: visible)
        let rebuilt = FrameCalculator.frame(
            relativePosition: relative,
            size: original.size,
            screenVisibleFrame: visible,
            minSize: NSSize(width: 100, height: 100)
        )
        XCTAssertEqual(rebuilt.origin.x, original.origin.x, accuracy: 0.001)
        XCTAssertEqual(rebuilt.origin.y, original.origin.y, accuracy: 0.001)
    }

    func testFrameFromRelativePositionClampsSizeToScreen() {
        let visible = NSRect(x: 0, y: 0, width: 800, height: 600)
        let frame = FrameCalculator.frame(
            relativePosition: CGPoint(x: 0.5, y: 0.5),
            size: NSSize(width: 1200, height: 900),
            screenVisibleFrame: visible,
            minSize: NSSize(width: 100, height: 100)
        )
        XCTAssertEqual(frame.size, NSSize(width: 800, height: 600))
    }

    // MARK: - Content-hugging growth (anchored to the edge it is nearest)
    //
    // `visible` is a *visible* frame throughout: its `maxY` is the bottom of
    // the menu bar, not the top of the display, so "would go under the menu
    // bar" and "would go off the top" are the same line here.

    private let hugMinSize = NSSize(width: 200, height: 100)
    private let hugVisible = NSRect(x: 0, y: 0, width: 1600, height: 1000)

    /// Offsets read the way a user sees them: `top` down from the visible
    /// area's top edge, `left` right from its left edge.
    private func hugFrame(left: CGFloat, top: CGFloat, size: NSSize) -> NSRect {
        FrameCalculator.frame(
            topLeftOffset: CGPoint(x: left, y: top),
            size: size,
            screenVisibleFrame: hugVisible)
    }

    /// One step of a fit, anchors chosen fresh — what a resize that is not part
    /// of a running gesture does.
    private func hugged(_ current: NSRect, to desired: NSSize) -> NSRect {
        hugged(current, to: desired, holding: nil).frame
    }

    /// One step of a fit that may be continuing a gesture: `holding` is what the
    /// previous step returned, and the anchors come back out for the next one.
    private func hugged(
        _ current: NSRect, to desired: NSSize, holding anchors: FrameAnchors?
    ) -> (frame: NSRect, anchors: FrameAnchors) {
        FrameCalculator.contentHuggingFrame(
            currentFrame: current,
            desiredFrameSize: desired,
            screenVisibleFrame: hugVisible,
            minSize: hugMinSize,
            anchors: anchors)
    }

    /// A window nowhere near an edge has no edge to hold, so it grows the way
    /// reading does: down and to the right, from the corner it already had.
    func testContentHuggingGrowsDownAndRightWhenNowhereNearAnEdge() {
        let current = hugFrame(left: 400, top: 300, size: NSSize(width: 500, height: 300))
        let grown = hugged(current, to: NSSize(width: 560, height: 420))

        XCTAssertEqual(grown.minX, 400, "the left edge it grew from stays put")
        XCTAssertEqual(grown.maxY, current.maxY, "the top edge it grew from stays put")
        XCTAssertEqual(grown.size, NSSize(width: 560, height: 420))
    }

    /// "If the window is close to the bottom of the screen and it is resized
    /// smaller, move it down to preserve the distance to the bottom."
    func testAWindowNearTheBottomKeepsItsDistanceWhenItShrinks() {
        // 40pt of daylight under it, 560 above: the bottom is the near edge.
        let current = hugFrame(left: 300, top: 560, size: NSSize(width: 500, height: 400))
        XCTAssertEqual(current.minY, 40)

        let shrunk = hugged(current, to: NSSize(width: 500, height: 300))

        XCTAssertEqual(shrunk.height, 300)
        XCTAssertEqual(shrunk.minY, 40, "the gap under it is what it holds, so its bottom does not move")
    }

    /// "If the window grows vertically and that would put its bottom off the
    /// screen, move it up as it grows."
    func testAWindowNearTheBottomMovesUpAsItGrows() {
        let current = hugFrame(left: 300, top: 560, size: NSSize(width: 500, height: 400))
        let grown = hugged(current, to: NSSize(width: 500, height: 600))

        XCTAssertEqual(grown.height, 600, "it got the height it asked for")
        XCTAssertEqual(grown.minY, 40, "by rising, not by hanging off the bottom")
    }

    /// "...until it would start going off the top or go under the menu bar." At
    /// that point there is nowhere left to move, so the growth stops instead.
    func testGrowthStopsAtTheTopOnceThereIsNowhereLeftToMove() {
        let current = hugFrame(left: 300, top: 560, size: NSSize(width: 500, height: 400))
        let grown = hugged(current, to: NSSize(width: 500, height: 1400))

        XCTAssertEqual(grown.height, hugVisible.height, "the height is capped at the screen")
        XCTAssertEqual(grown.maxY, hugVisible.maxY, "and it stops flush with the menu bar")
        XCTAssertEqual(grown.minY, hugVisible.minY)
    }

    /// "If the window is close to the top of the screen, don't move it
    /// vertically — only resize it, until it reaches the bottom of the screen."
    func testAWindowNearTheTopGrowsDownwardWithoutMoving() {
        let current = hugFrame(left: 300, top: 40, size: NSSize(width: 500, height: 300))
        let grown = hugged(current, to: NSSize(width: 500, height: 600))

        XCTAssertEqual(grown.maxY, current.maxY, "its top does not move")
        XCTAssertEqual(grown.height, 600)

        // Exactly reaching the bottom is still not a reason to move.
        let flush = hugged(current, to: NSSize(width: 500, height: 960))
        XCTAssertEqual(flush.maxY, current.maxY)
        XCTAssertEqual(flush.minY, hugVisible.minY, "flush with the bottom, having not moved")
    }

    /// "...if it reaches the bottom of the screen, start moving the window up
    /// until it would go off the screen at the top."
    func testAWindowNearTheTopMovesUpOnlyOnceItHasReachedTheBottom() {
        let current = hugFrame(left: 300, top: 40, size: NSSize(width: 500, height: 300))
        let grown = hugged(current, to: NSSize(width: 500, height: 1000))

        XCTAssertEqual(grown.height, 1000)
        XCTAssertEqual(grown.maxY, hugVisible.maxY, "it gave up its 40pt of headroom to fit")
    }

    /// The same rule, turned on its side: a window near the right edge holds
    /// its distance to the right edge, shrinking and growing against it.
    func testTheSameRuleHoldsAgainstTheRightEdge() {
        // 40pt of daylight to its right, 1060 to its left.
        let current = hugFrame(left: 1060, top: 40, size: NSSize(width: 500, height: 300))
        XCTAssertEqual(current.maxX, 1560)

        let shrunk = hugged(current, to: NSSize(width: 400, height: 300))
        XCTAssertEqual(shrunk.width, 400)
        XCTAssertEqual(shrunk.maxX, 1560, "shrinking walks it back toward the right edge")

        let grown = hugged(current, to: NSSize(width: 700, height: 300))
        XCTAssertEqual(grown.width, 700)
        XCTAssertEqual(grown.maxX, 1560, "growing pushes it left rather than off the screen")

        let overgrown = hugged(current, to: NSSize(width: 2000, height: 300))
        XCTAssertEqual(overgrown.width, hugVisible.width, "the width is capped at the screen")
        XCTAssertEqual(overgrown.minX, hugVisible.minX)
    }

    /// A window near the left edge is the mirror: it holds its left margin and
    /// grows right, and only moves once it has run out of screen.
    func testAWindowNearTheLeftEdgeGrowsRightwardWithoutMoving() {
        let current = hugFrame(left: 40, top: 40, size: NSSize(width: 500, height: 300))

        let grown = hugged(current, to: NSSize(width: 1000, height: 300))
        XCTAssertEqual(grown.minX, 40, "its left edge does not move")
        XCTAssertEqual(grown.width, 1000)

        let pushed = hugged(current, to: NSSize(width: 1600, height: 300))
        XCTAssertEqual(pushed.width, 1600)
        XCTAssertEqual(pushed.minX, hugVisible.minX, "it gave up its 40pt margin to fit")
    }

    /// `minSize` is a promise, and a screen too small to keep it is not a
    /// reason to break it: the window overhangs rather than collapsing.
    func testAWindowKeepsItsMinimumOnAScreenTooSmallForIt() {
        let tiny = NSRect(x: 0, y: 0, width: 150, height: 60)
        let fitted = FrameCalculator.contentHuggingFrame(
            currentFrame: tiny,
            desiredFrameSize: NSSize(width: 10, height: 10),
            screenVisibleFrame: tiny,
            minSize: hugMinSize).frame

        XCTAssertEqual(fitted.size, hugMinSize, "never collapse below minSize")
        XCTAssertEqual(fitted.minX, tiny.minX, "flush with the left, overhanging the right")
        XCTAssertEqual(fitted.maxY, tiny.maxY, "flush with the top, overhanging the bottom")
    }

    /// A window tucked into a corner holds that corner on the way out and on
    /// the way back, so a slider dragged up and down leaves it where it was
    /// even without an anchor being carried between the steps.
    func testGrowingAndShrinkingBackLeavesTheWindowWhereItWas() {
        // Tucked into the bottom-right corner, where both axes move.
        let current = hugFrame(left: 1060, top: 560, size: NSSize(width: 500, height: 400))

        let grown = hugged(current, to: NSSize(width: 700, height: 600))
        let back = hugged(grown, to: NSSize(width: 500, height: 400))

        XCTAssertEqual(back, current)
    }

    // MARK: - Holding the anchor across a gesture

    /// The case a corner-tucked window hides. A window that starts equidistant
    /// keeps its *start* edge and grows in place — and having grown, it is no
    /// longer equidistant: the end edge is now the nearer one, so a step that
    /// re-reads the anchor shrinks it back toward the end instead and leaves
    /// the window 100pt right of where it started. Nothing about either reading
    /// is wrong; a stateless nearest-edge rule simply cannot be reversible
    /// under both, which is why the anchor is held for the gesture.
    func testAWindowInTheMiddleComesBackToWhereItStarted() {
        // 400 of daylight on the left, 400 on the right: a dead tie.
        let current = hugFrame(left: 600, top: 300, size: NSSize(width: 400, height: 300))
        XCTAssertEqual(current.minX - hugVisible.minX, hugVisible.maxX - current.maxX,
                       "a dead tie: 600pt of daylight either side")

        let out = hugged(current, to: NSSize(width: 600, height: 300), holding: nil)
        XCTAssertEqual(out.frame.minX, current.minX, "the tie keeps the start edge")

        let back = hugged(out.frame, to: NSSize(width: 400, height: 300), holding: out.anchors)
        XCTAssertEqual(back.frame, current, "the move out is the move back")
    }

    /// What the held anchor is protecting against, stated as the bug: the same
    /// two steps with the anchor re-read each time walk the window away.
    func testRereadingTheAnchorEachStepWalksTheWindow() {
        let current = hugFrame(left: 600, top: 300, size: NSSize(width: 400, height: 300))

        let out = hugged(current, to: NSSize(width: 600, height: 300))
        let back = hugged(out, to: NSSize(width: 400, height: 300))

        XCTAssertEqual(back.minX, 800, "200pt to the right of where it started")
        XCTAssertNotEqual(back, current)
    }

    /// An end anchor is held even when the window has drifted into territory
    /// where the start edge would now read as nearer — that is the whole point
    /// of carrying it.
    func testAHeldEndAnchorOutranksWhereTheWindowNowSits() {
        let current = hugFrame(left: 1060, top: 300, size: NSSize(width: 500, height: 300))
        let held = FrameAnchors(horizontal: .end, vertical: .start)

        let shrunk = hugged(current, to: NSSize(width: 200, height: 300), holding: held)

        XCTAssertEqual(shrunk.frame.maxX, current.maxX, "the right edge is what it holds")
        XCTAssertEqual(shrunk.anchors, held, "and it hands the same anchors on")
    }

    /// A fresh fit reports the anchors it chose, per axis, so the caller has
    /// something to hand back.
    func testAFitReportsTheAnchorsItChose() {
        // Near the right edge, near the top: end horizontally, start vertically.
        let current = hugFrame(left: 1060, top: 20, size: NSSize(width: 500, height: 300))

        let fit = hugged(current, to: NSSize(width: 520, height: 320), holding: nil)

        XCTAssertEqual(fit.anchors, FrameAnchors(horizontal: .end, vertical: .start))
    }

    // MARK: - One rule for how long an axis may be

    /// `minSize` beats the screen everywhere, not just in the content-hugging
    /// path. Restoring from proportions, re-placing on a new screen and
    /// validating a frame used to clamp to the screen and collapse the window
    /// below its own minimum — the same window came back a different size
    /// depending on which path it arrived through.
    func testEveryPathKeepsAMinimumLargerThanTheScreen() {
        let tiny = NSRect(x: 0, y: 0, width: 150, height: 60)
        let floor = NSSize(width: 200, height: 100)

        let absolute = FrameCalculator.absoluteFrame(
            proportionalX: 0.5, proportionalY: 0.5,
            width: 10, height: 10,
            screenVisibleFrame: tiny, minSize: floor)
        XCTAssertEqual(absolute.size, floor)

        let relative = FrameCalculator.frame(
            relativePosition: CGPoint(x: 0.5, y: 0.5),
            size: NSSize(width: 10, height: 10),
            screenVisibleFrame: tiny, minSize: floor)
        XCTAssertEqual(relative.size, floor)

        let validated = FrameCalculator.validateFrame(
            NSRect(x: 0, y: 0, width: 10, height: 10),
            screenVisibleFrame: tiny, minSize: floor)
        XCTAssertEqual(validated.size, floor)

        let hugging = FrameCalculator.contentHuggingFrame(
            currentFrame: tiny, desiredFrameSize: NSSize(width: 10, height: 10),
            screenVisibleFrame: tiny, minSize: floor).frame
        XCTAssertEqual(hugging.size, floor)
    }
}
