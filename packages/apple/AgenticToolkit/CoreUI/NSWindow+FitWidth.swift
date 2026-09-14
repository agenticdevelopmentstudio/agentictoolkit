import AppKit

extension NSWindow {
    /// Keeps the window at least wide enough for `contentWidth` of content: sets
    /// `minSize.width` to it so the user can't drag it narrower, and widens the frame
    /// if it is narrower now. A window already wider is left alone — the user owns any
    /// width beyond what the content needs. The minimum follows the content both ways
    /// (a long row leaving lowers it again), so the caller folds in any floor of its
    /// own.
    ///
    /// The window grows leftwards when growing rightwards would push it past the
    /// visible frame's right edge (a window docked top-right stays docked), and its
    /// left edge never goes past the visible frame's left edge.
    ///
    /// The width counterpart of `fitHeight(toContentHeight:)`, for content that
    /// can't give way — Stenographer's Sessions window keeps each row's breadcrumb
    /// whole this way.
    public func ensureMinimumContentWidth(_ contentWidth: CGFloat) {
        guard contentWidth > 0 else { return }
        let needed = frameRect(forContentRect: NSRect(x: 0, y: 0, width: contentWidth, height: 0)).width
        minSize.width = needed
        guard frame.width + 1 < needed else { return }
        var newFrame = frame
        newFrame.size.width = needed
        if let visible = (screen ?? NSScreen.main)?.visibleFrame {
            if newFrame.maxX > visible.maxX {
                newFrame.origin.x = visible.maxX - needed
            }
            newFrame.origin.x = max(newFrame.origin.x, visible.minX)
        }
        setFrame(newFrame, display: true, animate: false)
    }
}
