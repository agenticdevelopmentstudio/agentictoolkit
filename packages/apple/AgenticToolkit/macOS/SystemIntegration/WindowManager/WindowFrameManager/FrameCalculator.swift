import AppKit
import AgenticToolkitCore

/// Which edge of an axis a content-hugging resize holds on to: the visible
/// area's **start** — its left, or its top — or its **end**, its right or its
/// bottom. A window holding its start edge grows right and down; one holding
/// its end edge grows left and up, and shrinks back toward the edge it is
/// tucked against.
public enum FrameAnchor: Sendable, Equatable {
    case start
    case end
}

/// The edge each axis of a content-hugging resize is holding. Returned by
/// `FrameCalculator.contentHuggingFrame` and handed back to it on the next step
/// of the same gesture — see that method for why the anchor has to be
/// remembered rather than re-read.
public struct FrameAnchors: Sendable, Equatable {
    public var horizontal: FrameAnchor
    public var vertical: FrameAnchor

    public init(horizontal: FrameAnchor, vertical: FrameAnchor) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

/// Pure functions for proportional frame math. No side effects, fully testable.
public enum FrameCalculator {

    /// How long an axis is allowed to be: never below `minLength`, never past
    /// the screen — and when those two disagree, `minLength` wins.
    ///
    /// That last clause is the whole of `max(visibleLength, minLength)`. A
    /// window whose minimum is larger than the screen keeps its minimum and
    /// overhangs, because collapsing it below `minSize` breaks the promise
    /// `minSize` makes. Four places used to spell this rule and only one of them
    /// said that part, so the same window came back a different size depending
    /// on whether it was being restored from proportions, re-placed on a new
    /// screen, resized by its own content, or merely validated.
    static func clampedLength(
        _ desired: CGFloat,
        min minLength: CGFloat,
        visible visibleLength: CGFloat
    ) -> CGFloat {
        Swift.min(Swift.max(desired, minLength), Swift.max(visibleLength, minLength))
    }

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
        let clampedWidth = clampedLength(
            width, min: minSize.width, visible: screenVisibleFrame.width)
        let clampedHeight = clampedLength(
            height, min: minSize.height, visible: screenVisibleFrame.height)

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
        let width = clampedLength(size.width, min: minSize.width, visible: visible.width)
        let height = clampedLength(size.height, min: minSize.height, visible: visible.height)
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
    /// **The anchor is chosen once per gesture, not once per step.** Pass the
    /// `anchors` a previous step returned and they are used again rather than
    /// re-read from the frame; pass `nil` and rule 1 picks them.
    ///
    /// Re-reading them every step is what stops a slider dragged out and back
    /// from coming home. On a 1000-wide axis a window at offset 400, 200 long,
    /// is exactly equidistant, so it keeps its start edge and grows to 300 in
    /// place. But at 400/300 the nearer edge is now the *end* — so shrinking
    /// back to 200 anchors on the end instead and leaves the window at 500.
    /// Neither reading is wrong on its own: a resize is reversible under a
    /// start anchor (the offset is what is held) and reversible under an end
    /// anchor (offset + length is what is held), and no stateless nearest-edge
    /// rule is reversible under both. Holding the anchor for the length of the
    /// gesture is what makes the move out the move back.
    ///
    /// Returns the anchors it used, for the caller to hand back on the next
    /// step. The *clamp* can still move a window legitimately — growth with
    /// nowhere left to go gives up the margin on the near side — and shrinking
    /// back does not undo that; the window is where it had to go to fit.
    public static func contentHuggingFrame(
        currentFrame: NSRect,
        desiredFrameSize: NSSize,
        screenVisibleFrame visible: NSRect,
        minSize: NSSize,
        anchors: FrameAnchors? = nil
    ) -> (frame: NSRect, anchors: FrameAnchors) {
        // Both axes are solved in the user's terms — offsets from the visible
        // area's left and top edges, growing right and down — so "the edge it
        // started from" is the same sentence twice rather than one sentence and
        // its mirror image in AppKit's upward y.
        let offset = topLeftOffset(windowFrame: currentFrame, screenVisibleFrame: visible)
        let horizontal = fittedAxis(
            offset: offset.x, length: currentFrame.width,
            desiredLength: desiredFrameSize.width,
            visibleLength: visible.width, minLength: minSize.width,
            anchor: anchors?.horizontal
        )
        let vertical = fittedAxis(
            offset: offset.y, length: currentFrame.height,
            desiredLength: desiredFrameSize.height,
            visibleLength: visible.height, minLength: minSize.height,
            anchor: anchors?.vertical
        )
        let fitted = frame(
            topLeftOffset: CGPoint(x: horizontal.offset, y: vertical.offset),
            size: NSSize(width: horizontal.length, height: vertical.length),
            screenVisibleFrame: visible
        )
        return (fitted, FrameAnchors(horizontal: horizontal.anchor, vertical: vertical.anchor))
    }

    /// One axis of `contentHuggingFrame`. `offset` is the gap from the visible
    /// area's start edge (its left, or its top) to the window's own start edge.
    ///
    /// Split out and pure because the rule is the same rule on both axes, and a
    /// second spelling of it is a second place for left/right and top/bottom to
    /// drift apart (`dry`).
    ///
    /// - Parameter anchor: the edge to hold, or `nil` to read it off the frame.
    /// - Returns: the new offset and length, and the anchor that produced them
    ///   — which is what the next step of the same gesture passes back in.
    static func fittedAxis(
        offset: CGFloat,
        length: CGFloat,
        desiredLength: CGFloat,
        visibleLength: CGFloat,
        minLength: CGFloat,
        anchor: FrameAnchor? = nil
    ) -> (offset: CGFloat, length: CGFloat, anchor: FrameAnchor) {
        let newLength = clampedLength(desiredLength, min: minLength, visible: visibleLength)
        let gapStart = offset
        let gapEnd = visibleLength - offset - length
        // `<`, not `<=`: a window equidistant from both edges — including one
        // already filling the axis, where both gaps are zero — keeps its start
        // edge, the anchor it had before any of this moved it.
        let held = anchor ?? (gapEnd < gapStart ? .end : .start)
        var newOffset = held == .end ? offset + length - newLength : offset
        // Push back on screen: past the end edge first, then the start edge, so
        // a window that cannot fit either way ends up flush with the start
        // rather than flush with the end.
        newOffset = Swift.min(newOffset, visibleLength - newLength)
        newOffset = Swift.max(newOffset, 0)
        return (newOffset, newLength, held)
    }

    /// Ensures a frame is fully visible within a screen's visible area.
    public static func validateFrame(
        _ frame: NSRect,
        screenVisibleFrame visible: NSRect,
        minSize: NSSize
    ) -> NSRect {
        var result = frame

        // Never below `minSize`, never past the screen — and `minSize` wins
        // when those disagree, the same rule every other sizing path here uses.
        result.size.width = clampedLength(
            result.size.width, min: minSize.width, visible: visible.width)
        result.size.height = clampedLength(
            result.size.height, min: minSize.height, visible: visible.height)

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
