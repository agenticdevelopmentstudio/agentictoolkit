import AppKit

/// A project window, as Cocoa Scripting sees it.
///
/// Holds the controller weakly: a script can keep a reference to a window it
/// then closes, and a wrapper is not a reason to keep a window's whole object
/// graph — and its database handle — alive.
@MainActor
@objc(ScriptableProjectWindow)
public final class ScriptableProjectWindow: NSObject {

    public weak var controller: ComposableTabsWindowController?

    public init(controller: ComposableTabsWindowController) {
        self.controller = controller
        super.init()
    }

    /// The persisted `git_repo.id` — one window per project, so the project's
    /// id *is* the window's id, and a script does not have to hold on to a
    /// window reference across a close and reopen.
    @objc var uniqueID: String { self.controller?.project.id.uuidString ?? "" }

    @objc var name: String { self.controller?.project.displayName ?? "" }

    @objc var helpVisible: Bool {
        get { self.controller?.isHelpVisible ?? false }
        set { self.controller?.setHelpVisible(newValue) }
    }

    /// Which drawer tab is showing. Read-only while Help is the only tab —
    /// a setter with one legal value is a setter that cannot fail informatively.
    ///
    /// Reached through `helpDrawerTabID`, a plain `String?`, rather than the
    /// drawer itself: the drawer's type is deprecated and this project builds
    /// warnings as errors, so naming it here would spread the quarantine over
    /// a class that has nothing else to do with drawers.
    @objc var drawerTab: String { self.controller?.helpDrawerTabID ?? "" }

    @objc var searchQuery: String {
        get { self.controller?.searchQuery ?? "" }
        set { self.controller?.searchQuery = newValue }
    }

    @objc var selectedTab: String {
        get { self.controller?.selectedTabIdentifier ?? "" }
        set { self.controller?.selectedTabIdentifier = newValue }
    }

    public override nonisolated var objectSpecifier: NSScriptObjectSpecifier? {
        final class Box: @unchecked Sendable { var value: NSScriptObjectSpecifier? }
        let box = Box()
        MainActor.assumeIsolated {
            guard let appDescription = NSApp.classDescription as? NSScriptClassDescription else { return }
            box.value = NSUniqueIDSpecifier(
                containerClassDescription: appDescription,
                containerSpecifier: nil,
                key: "projectWindows",
                uniqueID: self.uniqueID)
        }
        return box.value
    }
}
