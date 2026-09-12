import AgenticDeveloperToolkitUI
import AppKit

/// Everything a pane needs from whatever is holding it — four requests and two
/// questions, none of which mention a split view, a layout tree, a tab or a
/// project.
///
/// The asymmetry is deliberate. A pane's buttons produce **requests**, not
/// actions: the host is free to refuse (the last leaf in a tab has nowhere to
/// go), to substitute (a request to minimize leading resolves to trailing when
/// the pane sits in the trailing slot), or to do something entirely different
/// with the same click. The pane changes its own state only when the host calls
/// `setMinimized(to:)` or `setZoomed(_:)` back to say what it did.
///
/// That is what lets the same `PaneViewController` be dropped into a container
/// with different rules and still be correct — the container that knows the
/// rules is the one enforcing them (`separation-of-concerns`).
@MainActor
public protocol PaneHost: AnyObject {

    /// The user pressed close. The host removes the pane, or declines.
    func paneDidRequestClose(_ pane: PaneViewController)

    /// The user pressed zoom. Toggling is the host's decision: it knows whether
    /// this pane is the currently zoomed one.
    func paneDidRequestZoom(_ pane: PaneViewController)

    /// The user picked an arrow. `edge` is what they clicked, not necessarily
    /// what will happen — the host resolves it against the layout.
    func paneDidRequestMinimize(_ pane: PaneViewController, to edge: PaneEdge)

    /// The user pressed restore, from the title bar or from the rail.
    func paneDidRequestRestore(_ pane: PaneViewController)

    /// Which arrows the minimize picker should enable. Empty disables the
    /// control outright — a pane filling its tab has no sibling to hand space
    /// to.
    func availableMinimizeEdges(for pane: PaneViewController) -> Set<PaneEdge>

    /// Whether closing this pane is a thing the host would agree to.
    ///
    /// The other question, and the exception to "a pane's buttons produce
    /// requests, not actions": a host that will *never* let go of a pane owes
    /// the user a dim button rather than a live one that beeps. A host whose
    /// answer depends on the moment should keep answering `true` and refuse in
    /// `paneDidRequestClose(_:)` — this is for a rule, not for a mood.
    func canClose(_ pane: PaneViewController) -> Bool
}

public extension PaneHost {

    /// Defaulted, because most hosts have no rule to state: a container that
    /// will hand back any pane it is asked for never has to write this.
    func canClose(_ pane: PaneViewController) -> Bool { true }
}
