import AppKit

/// Everything Cocoa Scripting asks the app for about projects.
///
/// It hangs off `ProjectWindowManager` because that is already the answer to
/// "which project windows are open" — a second registry would be a second
/// thing to keep in step with window closing.
///
/// Nothing here needs the `NSDrawer` deprecation quarantine: the drawer is
/// reached through `helpDrawerTabID`, a plain `String?`, so no deprecated type
/// appears in any of these signatures.
extension ProjectWindowManager {

    // MARK: - Windows

    public var scriptableProjectWindows: [ScriptableProjectWindow] {
        self.openWindowControllers.map(ScriptableProjectWindow.init(controller:))
    }

    public func scriptableProjectWindow(uniqueID: String) -> ScriptableProjectWindow? {
        self.scriptableProjectWindows.first { $0.uniqueID == uniqueID }
    }

    // MARK: - Tabs

    public var scriptableProjectTabs: [ScriptableProjectTab] {
        self.openWindowControllers.flatMap(\.scriptingTabs)
    }

    public func scriptableProjectTab(uniqueID: String) -> ScriptableProjectTab? {
        self.scriptableProjectTabs.first { $0.uniqueID == uniqueID }
    }

    // MARK: - Panes

    /// Every pane in every open project window.
    ///
    /// Each wrapper is told which window it came from. Only a pane on the
    /// front tab is in a view hierarchy, so a wrapper left to find its own
    /// window would report an empty project and tab for every pane behind a
    /// tab — the enumeration is the one place that always knows.
    public var scriptablePanes: [ScriptablePane] {
        self.openWindowControllers.flatMap { window in
            window.allPanes().map { ScriptablePane(pane: $0, in: window) }
        }
    }

    public func scriptablePane(uniqueID: String) -> ScriptablePane? {
        self.scriptablePanes.first { $0.uniqueID == uniqueID }
    }
}
