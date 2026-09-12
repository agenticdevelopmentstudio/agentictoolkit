import AppKit

extension NSWindow {
    /// Resizes the window so its height matches `contentHeight` (plus the title bar),
    /// anchored at the top edge and never extending past the bottom of the screen's
    /// visible area. A no-op when the resulting delta is under 1pt.
    ///
    /// The cap is the distance from the window's own top edge down to the bottom of
    /// the visible frame — not the screen's full height. Clamping to the height alone
    /// is only right for a window whose top is already at the top of the screen: one
    /// sitting lower grows straight past the dock, which is what the Sessions window
    /// did with a long list. The host is expected to make the content scroll once it
    /// exceeds what the cap allows.
    ///
    /// Shared by the toolkit's session-list panel and Stenographer's Sessions window —
    /// both size their window to a list's intrinsic content height.
    public func fitHeight(toContentHeight contentHeight: CGFloat) {
        guard contentHeight > 0 else { return }
        let titleBarHeight = frame.height - contentLayoutRect.height
        let visible = (screen ?? NSScreen.main)?.visibleFrame
        // The top edge stays put, so the available room is whatever lies beneath it.
        // A window whose top is already off-screen keeps at least its minimum height.
        let top = visible.map { min(frame.maxY, $0.maxY) } ?? frame.maxY
        let available = visible.map { max(top - $0.minY, minSize.height) } ?? .greatestFiniteMagnitude
        let newHeight = min(max(contentHeight + titleBarHeight, minSize.height), available)
        guard abs(frame.height - newHeight) > 1 else { return }
        var newFrame = frame
        newFrame.size.height = newHeight
        newFrame.origin.y = top - newHeight
        setFrame(newFrame, display: true, animate: false)
    }
}
