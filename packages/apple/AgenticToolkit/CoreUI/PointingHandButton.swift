import AppKit

/// A button that shows the pointing hand over itself **whether or not its window
/// is key**.
///
/// `addCursorRect` alone is not enough for the windows this toolkit puts on
/// screen. A floating panel beside the terminal the user is typing into is not
/// key, and AppKit honours cursor rects only in the key window — so the one
/// clickable thing in an unfocused list would look like the text around it,
/// which is exactly when a reader needs telling that it is a link. Setting the
/// cursor from the tracking area covers that case, and the cursor rect still
/// covers the ordinary one, where AppKit resets the cursor for us on the way
/// out.
public final class PointingHandButton: NSButton {
    private var hoverArea: NSTrackingArea?

    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        // `.activeAlways` rather than `.activeInKeyWindow`, for the same reason
        // the cursor rect is not sufficient.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    public override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    public override func mouseMoved(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    public override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}
