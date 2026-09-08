import AppKit

/// What a pane's *content* contributes to the chrome around it.
///
/// Six protocols, each opted into on its own and probed with `as?` — the idiom
/// `ComposableTabsPaneViewController` already uses for `PaneContentTeardown`
/// and `PaneContentRemovalConfirmation`. A pane whose content implements none
/// of them still works; every surface below has a fallback, and
/// `PaneViewController` is the one place those fallbacks live.
///
/// All six are class-bound. Two carry a settable change callback, and a pane
/// installs its own closure into it through the existential — an assignment
/// that does not compile through a struct-capable protocol.

/// Content that names itself, and says when the name changed.
///
/// The seam is here so that content whose name is its own to decide — a file
/// browser retitling itself when its root changes — can say so without the
/// title bar ever learning what a file browser is. Nothing conforms yet: every
/// pane on this branch is named by `PaneViewController.fallbackTitle`, which
/// `ComposableTabsPaneViewController` overrides with `paneName`. The archetype
/// is what the protocol is for, not a description of a caller that exists.
@MainActor
public protocol PaneTitleProviding: AnyObject {
    var paneTitle: String { get }
    /// Called by the content when `paneTitle` would now answer differently.
    var onPaneTitleChange: (() -> Void)? { get set }
}

/// Content that puts its own controls in the title bar's middle.
///
/// This is the "space between the title and the gear, abstracted to accept
/// controls appropriate for the pane" from the feature request.
@MainActor
public protocol PaneAccessoryProviding: AnyObject {
    func makePaneAccessoryViews() -> [NSView]
}

/// Content that adds rows to the gear popover, beneath the spacing control
/// every pane gets.
@MainActor
public protocol PaneOptionsProviding: AnyObject {
    func makePaneOptionRows() -> [NSView]
}

/// Content that draws itself as a glyph when the pane is minimized to a strip.
@MainActor
public protocol PaneMinimizedRepresenting: AnyObject {
    var paneMinimizedSymbolName: String { get }
    var paneMinimizedTooltip: String { get }
}

/// Content the window's search field can drive.
///
/// The field disables itself over a pane that does not implement this, so the
/// query always means "search *this* pane" rather than silently going nowhere.
@MainActor
public protocol PaneSearchable: AnyObject {
    var paneSearchPlaceholder: String { get }
    func paneSearch(for query: String)
}

/// Content that has a selection worth naming in the window footer.
@MainActor
public protocol PaneSelectionDescribing: AnyObject {
    /// The trailing segment of the footer's display path, or `nil` for a pane
    /// with nothing selected — in which case the path stops at the pane.
    var paneSelectionDescription: String? { get }
    /// Called by the content when `paneSelectionDescription` would now answer
    /// differently.
    var onPaneSelectionChange: (() -> Void)? { get set }
}
