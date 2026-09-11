import AgenticToolkitCore
import Foundation

/// A directory the project can be worked in: the repository's own checkout or
/// one of its linked worktrees. The project controller opens one tab group
/// per checkout.
public struct ProjectCheckout: Hashable, Sendable {
    public let directory: URL
    public let branch: String?
    public let isMain: Bool

    public init(directory: URL, branch: String?, isMain: Bool) {
        self.directory = directory.standardizedFileURL
        self.branch = branch
        self.isMain = isMain
    }

    /// Path-derived so a checkout keeps its identity across branch switches.
    /// djb2 over the standardized path, in hex, so it is safe in a command id.
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
