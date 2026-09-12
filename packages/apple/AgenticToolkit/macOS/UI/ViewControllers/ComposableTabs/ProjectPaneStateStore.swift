import Foundation

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
/// The guarantee that buys is one-directional and worth stating exactly:
/// nothing this class writes can land on a key a content pane chose, because
/// every key it writes starts with `prefix`. The other direction is a
/// documented reservation rather than a check — `ProjectWorkspace.setPaneState`
/// says the prefix is spoken for, and a content pane that writes
/// `chrome.something` anyway would still land on top of the chrome. Enforcing
/// it would mean a check on a path this class itself has to be allowed
/// through, which buys less than the sentence does.
///
/// **Cleanup is somebody else's.** `saveTabs` deletes every `pane_state` row
/// whose `node_id` is no longer a layout node, so a closed pane's state goes
/// with it and this class has no lifetime to manage. A pane that is *not* a
/// layout node — an editor inside the Document pane's own tabs — has to name
/// the layout node it belongs to instead; see `ownerNodeID`.
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

    /// The layout node these rows should live and die with, when that is not
    /// the pane's own node — `nil`, the common case, for a pane that *is* a
    /// layout node.
    ///
    /// The sweep above is the whole reason this exists. A pane nested inside
    /// another pane's content — the Document pane's editors — has a node id
    /// that appears only in that pane's own stored layout, never in
    /// `layout_nodes`, so every row written against it is deleted on the next
    /// save and the pane comes back empty. Naming the enclosing layout node
    /// here writes the rows against *it* and folds the pane's own id into the
    /// key, so the state's lifetime is the enclosing pane's while two nested
    /// panes still cannot collide.
    ///
    /// Settable after `init` because a nested pane is built before the tree
    /// that knows which layout node owns it; `stampOwnershipOnChildren()` is
    /// what fills it in, along with everything else a subtree inherits.
    public var ownerNodeID: UUID?

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
    ///
    /// An owned store spells the pane's own id into the key, because its rows
    /// share one `node_id` with every other pane under the same owner.
    public func storageKey(for key: String) -> String {
        ownerNodeID == nil ? prefix + key : "\(prefix)\(nodeID.uuidString)." + key
    }

    /// The row's `node_id` — the owner when there is one, so the sweep keeps
    /// the row exactly as long as it keeps the owning pane.
    private var storageNodeID: UUID { ownerNodeID ?? nodeID }

    public func paneStateValue(forKey key: String) -> String? {
        project?.paneState(nodeID: storageNodeID, key: storageKey(for: key))
    }

    public func setPaneStateValue(_ value: String?, forKey key: String) {
        project?.setPaneState(nodeID: storageNodeID, key: storageKey(for: key), value: value)
    }
}
