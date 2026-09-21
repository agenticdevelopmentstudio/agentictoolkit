import AppKit

/// An explicit Tab order over a named handful of controls.
///
/// AppKit computes a key-view loop itself when nothing sets one, by walking the
/// view tree geometrically. That walk is a guess about what a window is for, and
/// in a window whose panes are built separately it guesses wrong in the way that
/// is hardest to live with: Tab leaves a field and never comes back to it. A
/// filter box in one pane and a composer in another are two *text* fields with a
/// transcript, a table, a segmented control and a pop-up button between them, and
/// the automatic loop threads all of those — so Tab walks out of the composer
/// into a row of buttons and the filter never has its turn.
///
/// Naming the participants says what Tab is for in this window: moving between
/// the places text can be typed. Everything else is reached by clicking it, which
/// is how it was reached anyway.
///
/// Disabled and hidden participants drop out of the cycle rather than becoming
/// dead stops — a Tab that lands on a greyed-out composer has taken the focus
/// somewhere it cannot be used and given no way back. So the loop is *rewired*
/// whenever enablement changes, which is why this is a type with a `refresh()`
/// rather than a one-shot function.
@MainActor
public final class KeyViewLoop {

    private let views: [NSView]

    /// The participants, in the order Tab should visit them. Held weakly is
    /// unnecessary: a loop is owned by the controller that owns the views.
    public init(_ views: [NSView]) {
        self.views = views
    }

    /// The first participant that can take focus right now — what a window uses
    /// as its `initialFirstResponder`.
    public private(set) var first: NSView?

    /// Rebuild the cycle from what is focusable at this moment.
    ///
    /// A single participant is wired to itself, which is what makes Tab a no-op
    /// rather than an escape when the composer is off: there is nowhere else
    /// text can be typed, so Tab stays put.
    public func refresh() {
        let live = views.filter(Self.canFocus)
        first = live.first
        guard let last = live.last else { return }
        var previous = last
        for view in live {
            previous.nextKeyView = view
            previous = view
        }
    }

    /// Whether Tab should stop here *now*.
    ///
    /// `acceptsFirstResponder` already answers it for a disabled or uneditable
    /// field. Hidden is asked separately because a view that is off screen still
    /// answers yes — a collapsed split-view pane hides its contents rather than
    /// disabling them, and the shelf in this window is usually collapsed.
    private static func canFocus(_ view: NSView) -> Bool {
        !view.isHiddenOrHasHiddenAncestor && view.acceptsFirstResponder
    }
}
