import AgenticToolkitCore
import Foundation

/// Decides which stored tabs to keep, which checkouts need a new tab group,
/// and which tabs point at directories that no longer exist. Pure: no disk
/// access except through `existsOnDisk`, so it is testable and the project
/// controller stays the only thing that acts on the answer.
public enum ProjectTabReconciler {
    public struct Plan {
        public let keep: [TabRecord]
        public let add: [ProjectCheckout]
        public let drop: [UUID]

        public var isUnchanged: Bool { add.isEmpty && drop.isEmpty }
    }

    /// - Parameter volumeIsMounted: Answers whether the volume that would hold
    ///   a directory is currently mounted. A record is dropped only when its
    ///   directory is missing *and* reachable storage says so, because
    ///   dropping deletes the tab, its layout tree and its remembered pane
    ///   state for good — an unplugged drive or a dismounted share must not
    ///   cost the user a tab they can never get back. Defaults to
    ///   `volumeIsMounted(for:projectDirectory:)`; injecting it keeps the
    ///   tests off real volumes.
    public static func plan(
        stored: [TabRecord],
        checkouts: [ProjectCheckout],
        projectDirectory: URL,
        existsOnDisk: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        volumeIsMounted: ((URL) -> Bool)? = nil
    ) -> Plan {
        // Resolved, not merely standardized, and for the same reason
        // `ProjectCheckout.init` resolves: a checkout's directory came from
        // `git worktree list` and a record's from whatever the window was
        // opened with, so an unresolved symlink on either side turns a match
        // into a miss — and a miss here adds a duplicate tab group for a
        // checkout that already has one.
        let projectDirectory = projectDirectory.resolvingSymlinksInPath()
        let isMounted = volumeIsMounted ?? {
            ProjectTabReconciler.volumeIsMounted(for: $0, projectDirectory: projectDirectory)
        }
        let checkoutDirectories = Set(checkouts.map(\.directory))
        var keep: [TabRecord] = []
        var drop: [UUID] = []
        var coveredDirectories = Set<URL>()

        for record in stored {
            let directory = (record.workingDirectory ?? projectDirectory).resolvingSymlinksInPath()
            let isGone = !checkoutDirectories.contains(directory) && !existsOnDisk(directory)
            if isGone && isMounted(directory) {
                drop.append(record.id)
            } else {
                keep.append(record)
                coveredDirectories.insert(directory)
            }
        }

        let add = checkouts.filter { !coveredDirectories.contains($0.directory) }
        return Plan(keep: keep, add: add, drop: drop)
    }

    /// Walks up to the deepest ancestor of `directory` that does exist. If
    /// that ancestor is `/Volumes` itself, the path names a mount point with
    /// nothing mounted on it. If it sits on a different volume than the
    /// project does, the storage the path belongs to is not the storage we
    /// can see — either way the directory is unreachable rather than deleted.
    ///
    /// The project directory is walked up the same way, so a caller reasoning
    /// about a directory that no longer exists at all still gets a comparable
    /// volume rather than `nil`.
    public static func volumeIsMounted(for directory: URL, projectDirectory: URL) -> Bool {
        let ancestor = deepestExistingAncestor(of: directory)
        guard ancestor.path != "/Volumes" else { return false }
        return volumeURL(of: ancestor) == volumeURL(of: deepestExistingAncestor(of: projectDirectory))
    }

    private static func deepestExistingAncestor(of directory: URL) -> URL {
        var candidate = directory.resolvingSymlinksInPath()
        while !FileManager.default.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { return candidate }
            candidate = parent
        }
        return candidate
    }

    private static func volumeURL(of directory: URL) -> URL? {
        try? directory.resourceValues(forKeys: [.volumeURLKey]).volume
    }

    /// One member per enabled edge, all in one group, all in the checkout's
    /// directory. `blueprint` is a factory, not a value: `layout_nodes.id` is
    /// a `TEXT PRIMARY KEY` and `saveTabs` inserts one member's `root` per
    /// call inside a single transaction, so members sharing one `LayoutNode`
    /// value would share one node id, the second insert would violate the
    /// primary key, and the whole save would roll back. Calling `blueprint()`
    /// once per edge gives each member's tree its own ids.
    public static func makeRecords(
        for checkout: ProjectCheckout,
        enabledEdges: [Edge],
        blueprint: () -> LayoutNode
    ) -> [TabRecord] {
        let groupID = UUID()
        return enabledEdges.map { edge in
            TabRecord(
                groupID: groupID,
                edge: edge,
                title: checkout.displayName,
                root: blueprint(),
                workingDirectory: checkout.directory
            )
        }
    }
}
