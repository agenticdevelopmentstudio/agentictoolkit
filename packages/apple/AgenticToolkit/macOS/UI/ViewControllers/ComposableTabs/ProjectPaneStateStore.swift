import Foundation
import AgenticToolkitCore

/// A pane's `PaneStateStore`, backed by the project database's `pane_state`
/// bag.
///
/// The bag is `(repo_id, node_id, key, value)` and was made untyped on purpose:
/// a pane that gains a remembered detail costs a key, not a migration. That is
/// exactly what the pane chrome needs, so there is no schema change here — only
/// this adapter, which is the one place that knows a pane's state lives in a
/// project at all.
///
/// **Keys are namespaced.** The same bag holds what a pane's *content*
/// remembers — the file browser's expanded folders, its selected file — written
/// through `ProjectWorkspace` with keys those panes chose. A chrome key and a
/// content key that happened to collide would be a bug visible in one pane type
/// and nowhere else, so everything written here is prefixed. The pane never
/// sees the prefix: it asks for `minimize.edge`, and where that lives is this
/// class's business (`separation-of-concerns`).
///
/// **Cleanup is somebody else's.** `saveTabs` deletes every `pane_state` row
/// whose `node_id` is no longer a layout node, so a closed pane's state goes
/// with it and this class has no lifetime to manage.
@MainActor
public final class ProjectPaneStateStore: PaneStateStore {

    /// Prefix for everything the pane chrome writes.
    public static let defaultPrefix = "chrome."

    /// Weak: a pane can outlive its project by the length of a window
    /// teardown, and a store that kept the project alive would keep the
    /// database open with it.
    private weak var project: ProjectWorkspace?
    private let nodeID: UUID
    private let prefix: String

    public init(
        project: ProjectWorkspace?,
        nodeID: UUID,
        prefix: String = ProjectPaneStateStore.defaultPrefix
    ) {
        self.project = project
        self.nodeID = nodeID
        self.prefix = prefix
    }

    /// Where `key` actually lives. Public so a test can assert the namespacing
    /// rather than assert a hard-coded string in two places.
    public func storageKey(for key: String) -> String { prefix + key }

    public func paneStateValue(forKey key: String) -> String? {
        project?.paneState(nodeID: nodeID, key: storageKey(for: key))
    }

    public func setPaneStateValue(_ value: String?, forKey key: String) {
        project?.setPaneState(nodeID: nodeID, key: storageKey(for: key), value: value)
    }
}
