import Foundation

/// One entry of `git worktree list --porcelain`.
public struct GitWorktree: Sendable, Equatable, Hashable {
    public let directory: URL
    public let head: String?
    public let branch: String?
    public let isMain: Bool
    public let isBare: Bool
    public let isDetached: Bool

    public init(directory: URL, head: String?, branch: String?, isMain: Bool, isBare: Bool, isDetached: Bool) {
        self.directory = directory
        self.head = head
        self.branch = branch
        self.isMain = isMain
        self.isBare = isBare
        self.isDetached = isDetached
    }

    /// Parses `worktree list --porcelain` output into worktrees.
    ///
    /// Records are separated by blank lines, but the parser does not rely on the
    /// blank line itself: it flushes the in-progress record whenever a new
    /// `worktree ` line starts, so a missing trailing blank line (or none between
    /// two records) still produces correct results. `bare` and `detached` are
    /// value-less attribute lines; `branch` arrives as a full ref
    /// (`refs/heads/<name>`) and is shortened to `<name>`. Per porcelain's
    /// contract, the main worktree is always the first entry, so `isMain` is
    /// simply "was this the first record flushed".
    public static func parse(porcelain output: String) -> [GitWorktree] {
        var results: [GitWorktree] = []
        var path: String?
        var head: String?
        var branch: String?
        var isBare = false
        var isDetached = false

        func flush() {
            guard let path else { return }
            results.append(GitWorktree(
                // A worktree path is a directory by definition, so say so
                // rather than letting Foundation stat it: the flavour decides
                // whether the URL carries a trailing slash, and these URLs are
                // compared for equality against directories built elsewhere.
                directory: URL(fileURLWithPath: path, isDirectory: true),
                head: head,
                branch: branch,
                isMain: results.isEmpty,
                isBare: isBare,
                isDetached: isDetached
            ))
        }

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("worktree ") {
                flush()
                path = String(line.dropFirst("worktree ".count))
                head = nil
                branch = nil
                isBare = false
                isDetached = false
            } else if line.hasPrefix("HEAD ") {
                head = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
            } else if line == "detached" {
                isDetached = true
            } else if line == "bare" {
                isBare = true
            }
        }
        flush()
        return results
    }
}
