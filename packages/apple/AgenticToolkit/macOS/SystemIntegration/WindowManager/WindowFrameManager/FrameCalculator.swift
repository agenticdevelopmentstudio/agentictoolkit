import AppKit
import AgenticToolkitCore

/// Pure functions for proportional frame math. No side effects, fully testable.
public enum FrameCalculator {

    /// Computes proportional coordinates for a window frame on a screen.
    public static func proportionalPosition(
        windowFrame: NSRect,
        screenVisibleFrame: NSRect
    ) -> (x: CGFloat, y: CGFloat) {
        let availableWidth = screenVisibleFrame.width - windowFrame.width
        let availableHeight = screenVisibleFrame.height - windowFrame.height

        let propX = availableWidth > 0
            ? ((windowFrame.origin.x - screenVisibleFrame.origin.x) / availableWidth).clamped(to: -0.1...1.1)
            : 0.5
        let propY = availableHeight > 0
            ? ((windowFrame.origin.y - screenVisibleFrame.origin.y) / availableHeight).clamped(to: -0.1...1.1)
            : 0.5

        return (propX, propY)
    }

    /// Computes an absolute frame from proportional coordinates and a screen.
    public static func absoluteFrame(
        proportionalX: CGFloat,
        proportionalY: CGFloat,
        width: CGFloat,
        height: CGFloat,
        screenVisibleFrame: NSRect,
        minSize: NSSize
    ) -> NSRect {
        let clampedWidth = Swift.min(Swift.max(width, minSize.width), screenVisibleFrame.width)
        let clampedHeight = Swift.min(Swift.max(height, minSize.height), screenVisibleFrame.height)

        let availableWidth = screenVisibleFrame.width - clampedWidth
        let availableHeight = screenVisibleFrame.height - clampedHeight

        let originX = screenVisibleFrame.origin.x + proportionalX * Swift.max(availableWidth, 0)
        let originY = screenVisibleFrame.origin.y + proportionalY * Swift.max(availableHeight, 0)

        return NSRect(x: originX, y: originY, width: clampedWidth, height: clampedHeight)
    }

    /// Computes a default frame for a spec on a screen.
    public static func defaultFrame(
        spec: WindowSpec,
        screenVisibleFrame: NSRect
    ) -> NSRect {
        absoluteFrame(
            proportionalX: spec.defaultPosition.proportionalX,
            proportionalY: spec.defaultPosition.proportionalY,
            width: spec.defaultSize.width,
            height: spec.defaultSize.height,
            screenVisibleFrame: screenVisibleFrame,
            minSize: spec.minSize
        )
    }

    // MARK: - Top-left anchored positioning (user's point of view)
    //
    // macOS frames have a bottom-left origin with y growing upward; from the
    // user's point of view the anchor that matters is the window's TOP-left
    // corner, with y growing downward from the top of the screen's visible
    // area. All "topLeft" values below use that user-POV convention.

    /// The window's top-left corner as an offset from the screen's
    /// visible-frame top-left. `x` points right, `y` points down.
    public static func topLeftOffset(
        windowFrame: NSRect,
        screenVisibleFrame visible: NSRect
    ) -> CGPoint {
        CGPoint(
            x: windowFrame.minX - visible.minX,
            y: visible.maxY - windowFrame.maxY
        )
    }

    /// Rebuilds an absolute frame from a user-POV top-left offset and size.
    public static func frame(
        topLeftOffset: CGPoint,
        size: NSSize,
        screenVisibleFrame visible: NSRect
    ) -> NSRect {
        NSRect(
            x: visible.minX + topLeftOffset.x,
            y: visible.maxY - topLeftOffset.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Where the window sits as a fraction of its available travel, top-left
    /// anchored: (0, 0) = flush top-left, (1, 1) = flush bottom-right,
    /// (0.5, 0.5) = centered. Clamped to 0...1; 0.5 when there is no travel
    /// (window fills the axis).
    public static func relativePosition(
        windowFrame: NSRect,
        screenVisibleFrame visible: NSRect
    ) -> CGPoint {
        let offset = topLeftOffset(windowFrame: windowFrame, screenVisibleFrame: visible)
        let travelX = visible.width - windowFrame.width
        let travelY = visible.height - windowFrame.height
        return CGPoint(
            x: travelX > 0 ? (offset.x / travelX).clamped(to: 0...1) : 0.5,
            y: travelY > 0 ? (offset.y / travelY).clamped(to: 0...1) : 0.5
        )
    }

    /// Rebuilds an absolute frame from a relative (travel-fraction) position.
    /// Used when the saved absolute offset no longer applies literally — a
    /// resolution change, or placing the window on a screen it has never
    /// been on.
    public static func frame(
        relativePosition: CGPoint,
        size: NSSize,
        screenVisibleFrame visible: NSRect,
        minSize: NSSize
    ) -> NSRect {
        let width = Swift.min(Swift.max(size.width, minSize.width), visible.width)
        let height = Swift.min(Swift.max(size.height, minSize.height), visible.height)
        let offset = CGPoint(
            x: relativePosition.x * Swift.max(visible.width - width, 0),
            y: relativePosition.y * Swift.max(visible.height - height, 0)
        )
        return frame(
            topLeftOffset: offset,
            size: NSSize(width: width, height: height),
            screenVisibleFrame: visible
        )
    }

    /// Frame for a content-hugging window that wants `desiredFrameSize`,
    /// kept whole and kept on screen.
    ///
    /// Two rules, applied to each axis independently:
    ///
    /// 1. **The window keeps the edge it is nearest.** A window sitting close
    ///    to the bottom of the screen holds its distance from the bottom, so
    ///    shrinking walks it back down and growing lifts it up; one sitting
    ///    close to the top holds its distance from the top and grows downward.
    ///    Ties keep the top-left edge, which is where a window that is nowhere
    ///    near an edge grows from.
    /// 2. **It is then pushed back on screen, and only then clamped.** Growth
    ///    that would carry the far edge past the screen moves the window
    ///    instead — as far as the near edge, never past it or under the menu
    ///    bar. A window with nowhere left to move stops growing: the size is
    ///    capped at the visible extent (`minSize` still wins, so a window on a
    ///    screen too small for it overhangs rather than collapsing) and its
    ///    content is left to scroll or compress.
    ///
    /// The two together are why a size slider can be dragged up and back down:
    /// the anchor is read from the frame each time, so the move out is the
    /// move back.
    public static func contentHuggingFrame(
        currentFrame: NSRect,
        desiredFrameSize: NSSize,
        screenVisibleFrame visible: NSRect,
        minSize: NSSize
    ) -> NSRect {
        // Both axes are solved in the user's terms — offsets from the visible
        // area's left and top edges, growing right and down — so "the edge it
        // started from" is the same sentence twice rather than one sentence and
        // its mirror image in AppKit's upward y.
        let offset = topLeftOffset(windowFrame: currentFrame, screenVisibleFrame: visible)
        let horizontal = fittedAxis(
            offset: offset.x, length: currentFrame.width,
            desiredLength: desiredFrameSize.width,
            visibleLength: visible.width, minLength: minSize.width
        )
        let vertical = fittedAxis(
            offset: offset.y, length: currentFrame.height,
            desiredLength: desiredFrameSize.height,
            visibleLength: visible.height, minLength: minSize.height
        )
        return frame(
            topLeftOffset: CGPoint(x: horizontal.offset, y: vertical.offset),
            size: NSSize(width: horizontal.length, height: vertical.length),
            screenVisibleFrame: visible
        )
    }

    /// One axis of `contentHuggingFrame`. `offset` is the gap from the visible
    /// area's start edge (its left, or its top) to the window's own start edge.
    ///
    /// Split out and pure because the rule is the same rule on both axes, and a
    /// second spelling of it is a second place for left/right and top/bottom to
    /// drift apart (`dry`).
    static func fittedAxis(
        offset: CGFloat,
        length: CGFloat,
        desiredLength: CGFloat,
        visibleLength: CGFloat,
        minLength: CGFloat
    ) -> (offset: CGFloat, length: CGFloat) {
        // `max(visibleLength, minLength)`: a window whose minimum is larger than
        // the screen keeps its minimum and overhangs. Collapsing it to the
        // screen would break the promise `minSize` makes.
        let newLength = Swift.min(
            Swift.max(desiredLength, minLength),
            Swift.max(visibleLength, minLength)
        )
        let gapStart = offset
        let gapEnd = visibleLength - offset - length
        // `<`, not `<=`: a window equidistant from both edges — including one
        // already filling the axis, where both gaps are zero — keeps its start
        // edge, the anchor it had before any of this moved it.
        var newOffset = gapEnd < gapStart ? offset + length - newLength : offset
        // Push back on screen: past the end edge first, then the start edge, so
        // a window that cannot fit either way ends up flush with the start
        // rather than flush with the end.
        newOffset = Swift.min(newOffset, visibleLength - newLength)
        newOffset = Swift.max(newOffset, 0)
        return (newOffset, newLength)
    }

    /// Ensures a frame is fully visible within a screen's visible area.
    public static func validateFrame(
        _ frame: NSRect,
        screenVisibleFrame visible: NSRect,
        minSize: NSSize
    ) -> NSRect {
        var result = frame

        // Enforce minimum size
        result.size.width = Swift.max(result.size.width, minSize.width)
        result.size.height = Swift.max(result.size.height, minSize.height)

        // Clamp size to screen
        result.size.width = Swift.min(result.size.width, visible.width)
        result.size.height = Swift.min(result.size.height, visible.height)

        // Push into visible bounds
        if result.maxX > visible.maxX {
            result.origin.x = visible.maxX - result.width
        }
        if result.origin.x < visible.origin.x {
            result.origin.x = visible.origin.x
        }
        if result.maxY > visible.maxY {
            result.origin.y = visible.maxY - result.height
        }
        if result.origin.y < visible.origin.y {
            result.origin.y = visible.origin.y
        }

        return result
    }
}
