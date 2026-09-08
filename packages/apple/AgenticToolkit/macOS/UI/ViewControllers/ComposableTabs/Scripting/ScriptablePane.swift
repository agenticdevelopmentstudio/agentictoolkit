import AppKit
import AgenticDeveloperToolkitUI

/// A pane, as Cocoa Scripting sees it.
///
/// A wrapper rather than conformances on the view controller itself: KVC
/// scripting keys are a vocabulary chosen for a dictionary (`minimized`,
/// `selection`), and pinning those names onto the view controller would make
/// the `.sdef` a constraint on every future rename inside the window.
@MainActor
@objc(ScriptablePane)
public final class ScriptablePane: NSObject {

    /// Held strongly, unlike `ScriptableProjectWindow.controller`, and the
    /// difference is deliberate rather than an oversight.
    ///
    /// That wrapper is weak because a window is a whole object graph — and a
    /// database handle — that a script has no business keeping alive after it
    /// closes the window. This one is a wrapper made fresh on every read, and
    /// Cocoa Scripting re-resolves a specifier through `panes` rather than
    /// holding a wrapper between events: nothing outlives the reply it was
    /// built for, so a strong reference here keeps a pane alive for exactly as
    /// long as answering one question takes. Not even `close pane` changes
    /// that — the pane is already out of the window's tree by the time this
    /// wrapper is released.
    public let pane: ComposableTabsPaneViewController

    /// The window the pane was enumerated from.
    ///
    /// Weak, because the wrapper is a value a script holds and the window is
    /// not its to keep alive.
    private weak var window: ComposableTabsWindowController?

    /// - Parameter window: the window this pane was found in. Required, not
    ///   optional: a pane on a tab that is not the front one has never been in
    ///   a window's view hierarchy, so a wrapper left to find its own window
    ///   through `view.window` names no project and no tab — for most of the
    ///   panes in a real window. Enumeration always knows which window it is
    ///   walking, and a lookup by id goes through the same enumeration, so
    ///   there is no caller that cannot say.
    public init(pane: ComposableTabsPaneViewController, in window: ComposableTabsWindowController) {
        self.pane = pane
        self.window = window
        super.init()
    }

    // MARK: - Scripting properties

    /// The persisted `layout_nodes.id`. A script that saw this pane yesterday
    /// can name it today, which is the whole reason not to invent an id here.
    @objc var uniqueID: String { self.pane.nodeID.uuidString }

    @objc var name: String { self.pane.resolvedTitle }

    /// The edge's own name, or `"no"`. One string rather than a boolean plus an
    /// edge, because "minimized" and "minimized *where*" are one fact and two
    /// properties can disagree about it.
    @objc var paneMinimized: String { self.pane.minimizedEdge?.rawValue ?? "no" }

    @objc var paneZoomed: Bool { self.pane.isZoomed }

    /// What the pane says is selected inside it, or empty. Empty rather than
    /// missing: AppleScript has no comfortable way to ask about a missing
    /// value, and "nothing is selected" is a real answer.
    @objc var paneSelection: String { self.pane.selectionDescription ?? "" }

    @objc var paneProject: String {
        self.window?.project.displayName ?? ""
    }

    /// Whether the pane is still in the window it was enumerated from.
    ///
    /// Not `@objc`: this is not in the dictionary. It exists because
    /// `closePane()` can be declined — the layout spec vetoes a tab's last pane
    /// and any fixed region — and "the request was delivered" is not the same
    /// answer as "the pane is gone".
    ///
    /// Asked of that one window rather than by re-running
    /// `ProjectWindowManager.shared.scriptablePane(uniqueID:)`: a pane cannot
    /// have moved to a *different* window between the request and this
    /// question, so one window's walk is a complete answer, where the manager's
    /// lookup would walk every open project to reach the same one. A window
    /// that has gone away has taken its panes with it, so a nil window reads as
    /// closed.
    public var isInWindow: Bool {
        guard let window = self.window else { return false }
        return window.allPanes().contains { $0 === self.pane }
    }

    /// The title of the project tab this pane is on.
    ///
    /// Found by asking the window which of its tabs contains this pane, rather
    /// than by storing a tab on the pane: a pane moves between tabs, and a
    /// stored answer would go stale with nothing to notice.
    @objc var paneTab: String {
        self.window?.tabGroup(containing: self.pane)?.title ?? ""
    }

    // MARK: - Actions

    /// Each action goes through the pane's host, so a script closes a pane by
    /// exactly the path the close button does — no second implementation of
    /// what closing means.
    public func closePane() {
        self.pane.host?.paneDidRequestClose(self.pane)
    }

    public func zoomPane() {
        self.pane.host?.paneDidRequestZoom(self.pane)
    }

    /// `to:` is an edge name, or anything else to restore. Restoring on an
    /// unrecognised name is deliberate: the alternative is guessing an edge,
    /// and a script that misspells "leading" would silently move a pane
    /// somewhere it did not ask for.
    ///
    /// The host may refuse — a pane whose split has no such axis stays where it
    /// is — and that refusal is the host's to make. `minimized` is what the
    /// script should read back, not this call.
    public func minimizePane(to edgeName: String) {
        guard let edge = PaneEdge(rawValue: edgeName) else {
            self.pane.host?.paneDidRequestRestore(self.pane)
            return
        }
        self.pane.host?.paneDidRequestMinimize(self.pane, to: edge)
    }

    // MARK: - Object specifier

    public override nonisolated var objectSpecifier: NSScriptObjectSpecifier? {
        applicationElementSpecifier(key: "panes") { self.uniqueID }
    }
}
