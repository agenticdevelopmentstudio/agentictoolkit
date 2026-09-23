import AppKit
import AgenticToolkitCore
import AgenticDeveloperToolkitUI

/// The inset "terminal" box: the Sessions window's output panel, and the
/// Conversations window's bubbles, which are drawn as that same panel.
///
/// One definition because the two are meant to read as the same object — a
/// reader who has seen a session's last output in the Sessions list should
/// recognise its conversation in the feed. Two copies of "6 and 1 and the
/// surface colour" drift the first time either window is tuned.
public enum TerminalBoxStyle {
    /// Tighter than a speech bubble's, so the box reads as a panel.
    public static let cornerRadius: CGFloat = 6
    /// One hairline, always.
    public static let borderWidth: CGFloat = 1

    public static func fill(_ palette: SemanticPalette) -> NSColor { palette.surfaceColor }
    public static func border(_ palette: SemanticPalette) -> NSColor { palette.borderColor }

    /// Gives `layer` the box's fixed shape. Colours come separately, from
    /// ``apply(_:to:)``, because they change with the theme and the shape does not.
    public static func shape(_ layer: CALayer?) {
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = borderWidth
    }

    /// Paints `layer` in the box's colours for `palette`.
    public static func apply(_ palette: SemanticPalette, to layer: CALayer?) {
        layer?.backgroundColor = fill(palette).cgColor
        layer?.borderColor = border(palette).cgColor
    }
}
