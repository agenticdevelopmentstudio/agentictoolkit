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

    public let pane: ComposableTabsPaneViewController

    /// The window the pane was enumerated from, when the caller knew it.
    ///
    /// Weak, because the wrapper is a value a script holds and the window is
    /// not its to keep alive.
    private weak var window: ComposableTabsWindowController?

    /// - Parameter window: the window this pane was found in. Pass it whenever
    ///   the caller already knows: a pane on a tab that is not the front one
    ///   has never been in a window's view hierarchy, so `view.window` is nil
    ///   and the pane cannot name its own project or tab. Enumeration always
    ///   knows; a lookup by id through the same enumeration does too.
    public init(pane: ComposableTabsPaneViewController, in window: ComposableTabsWindowController? = nil) {
        self.pane = pane
        self.window = window
        super.init()
    }

    /// Told, or asked. Asking is the fallback for a pane handed to this
    /// wrapper without its window — it answers for the front tab and returns
    /// nil for the rest, which is exactly the gap the parameter closes.
    private var enclosingWindow: ComposableTabsWindowController? {
        self.window ?? self.pane.enclosingProjectWindow
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
        self.enclosingWindow?.project.displayName ?? ""
    }

    /// The title of the project tab this pane is on.
    ///
    /// Found by asking the window which of its tabs contains this pane, rather
    /// than by storing a tab on the pane: a pane moves between tabs, and a
    /// stored answer would go stale with nothing to notice.
    @objc var paneTab: String {
        guard let window = self.enclosingWindow else { return "" }
        return window.scriptingTabs.first { tab in
            window.panes(inTab: tab.uniqueID).contains { $0 === self.pane }
        }?.name ?? ""
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
        // AppKit asks for this off the main actor; everything it reads is
        // main-thread state, and `NSScriptObjectSpecifier` is not Sendable, so
        // the result comes back in a Box. Same shape as
        // `ScriptableTerminalSession`.
        final class Box: @unchecked Sendable { var value: NSScriptObjectSpecifier? }
        let box = Box()
        MainActor.assumeIsolated {
            guard let appDescription = NSApp.classDescription as? NSScriptClassDescription else { return }
            box.value = NSUniqueIDSpecifier(
                containerClassDescription: appDescription,
                containerSpecifier: nil,
                key: "panes",
                uniqueID: self.uniqueID)
        }
        return box.value
    }
}
