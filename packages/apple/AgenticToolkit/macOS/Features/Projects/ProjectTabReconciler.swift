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

    public static func plan(
        stored: [TabRecord],
        checkouts: [ProjectCheckout],
        projectDirectory: URL,
        existsOnDisk: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> Plan {
        // Resolved, not merely standardized, and for the same reason
        // `ProjectCheckout.init` resolves: a checkout's directory came from
        // `git worktree list` and a record's from whatever the window was
        // opened with, so an unresolved symlink on either side turns a match
        // into a miss — and a miss here adds a duplicate tab group for a
        // checkout that already has one.
        let projectDirectory = projectDirectory.resolvingSymlinksInPath()
        let checkoutDirectories = Set(checkouts.map(\.directory))
        var keep: [TabRecord] = []
        var drop: [UUID] = []
        var coveredDirectories = Set<URL>()

        for record in stored {
            let directory = (record.workingDirectory ?? projectDirectory).resolvingSymlinksInPath()
            if checkoutDirectories.contains(directory) || existsOnDisk(directory) {
                keep.append(record)
                coveredDirectories.insert(directory)
            } else {
                drop.append(record.id)
            }
        }

        let add = checkouts.filter { !coveredDirectories.contains($0.directory) }
        return Plan(keep: keep, add: add, drop: drop)
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
