import AgenticToolkitCore
import Foundation

/// A directory the project can be worked in: the repository's own checkout or
/// one of its linked worktrees. The project controller opens one tab group
/// per checkout.
public struct ProjectCheckout: Hashable, Sendable {
    public let directory: URL
    public let branch: String?
    public let isMain: Bool

    /// `resolvingSymlinksInPath()`, not `standardizedFileURL`: the latter
    /// collapses `.` and `..` but leaves a symlink alone, and the two sides
    /// that get compared here reach a directory by different routes. `git
    /// worktree list` prints the fully resolved path (`/private/var/…`),
    /// while a workspace's directory comes from the path the user gave
    /// (`/var/…`) — the same directory, two URLs, and every `Set` lookup and
    /// dictionary key that pairs them would miss. Resolving also subsumes
    /// standardizing, so the `..` case below still normalizes.
    public init(directory: URL, branch: String?, isMain: Bool) {
        self.directory = directory.resolvingSymlinksInPath()
        self.branch = branch
        self.isMain = isMain
    }

    /// Path-derived so a checkout keeps its identity across branch switches.
    /// djb2 over the resolved path, in hex, so it is safe in a command id.
    public var identifier: String {
        var hash: UInt64 = 5381
        for byte in directory.path.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    public var displayName: String {
        branch ?? directory.lastPathComponent
    }

    /// Bare entries have no working directory to open a tab in.
    public static func checkouts(from worktrees: [GitWorktree]) -> [ProjectCheckout] {
        worktrees
            .filter { !$0.isBare }
            .map { ProjectCheckout(directory: $0.directory, branch: $0.branch, isMain: $0.isMain) }
    }
}
