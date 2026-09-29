import AppKit

/// A label that asks for a whole number of points.
///
/// Text measures in fractions, and layout places views on whole pixels: a name
/// that measures 293.5 wide is laid out 293 wide at 1x, and a label a fraction
/// narrower than its text truncates it. For a middle-truncating address that
/// fraction costs three letters, not half a point, and nothing stretches the
/// label back — the window was exactly as wide as the view hosting it asked
/// for. Asking for the whole point the text will be drawn in is what makes a
/// container's width floor and the text it was measured from agree.
///
/// Build it the way any label is built — `WholePointLabel(labelWithString:)` —
/// and use it wherever a label's text must come out whole in a container that
/// is sized to fit it.
public final class WholePointLabel: NSTextField {
    public override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        guard size.width != NSView.noIntrinsicMetric else { return size }
        return NSSize(width: ceil(size.width), height: size.height)
    }
}
