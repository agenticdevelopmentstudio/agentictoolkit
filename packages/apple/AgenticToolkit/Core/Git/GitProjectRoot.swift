import Foundation

/// Resolves the top-level project root for a working directory: the **main**
/// working tree of the topmost git repository that is *not* itself a
/// submodule of a parent. Moved out of Stenographer's `SessionEnricher` so
/// the app can resolve a folder the user picks to the same root the daemon
/// groups sessions under.
public enum GitProjectRoot {

    /// What a resolution actually learned, which is not the same as what
    /// `root(at:)` returns. `root(at:)` answers `nil` both for "git says
    /// there is no repository here" and for "git wouldn't answer", and only
    /// the first of those may be written down as permanent.
    public enum Resolution: Sendable, Equatable {
        /// The top-level project root for the directory.
        case resolved(String)
        /// git answered, and the answer is that this directory is not in a
        /// working tree. Permanent for as long as the directory is what it
        /// is today.
        case notAGitWorkingTree
        /// git could not answer. Nothing was learned, so nothing may be
        /// recorded.
        case undetermined
    }

    /// One `git` invocation's result, with "git said nothing" and "git
    /// couldn't say" kept apart. `output(cwd:_:)` flattens both to `nil`,
    /// which is fine for a value that is only ever written when non-empty;
    /// it is not fine for anything stamped at an algorithm version, because
    /// that decision is never revisited.
    public enum Outcome: Sendable, Equatable {
        /// Exit 0, with output.
        case output(String)
        /// Exit 0, nothing on stdout — an answer in its own right (an empty
        /// `--show-superproject-working-tree` means "not a submodule").
        case empty
        /// git exited non-zero, or could not be launched at all (`status` -1).
        case failed(status: Int32)
    }

    /// Returns the top-level project root for `cwd`, or nil when `cwd` isn't
    /// in a git working tree — and also when git simply wouldn't answer.
    /// Callers that write the result down must use ``resolve(at:)``, which
    /// keeps those two apart.
    public static func root(at cwd: String) -> String? {
        guard case .resolved(let root) = resolve(at: cwd) else { return nil }
        return root
    }

    /// ``root(at:)``, with the distinction between "no repository here" and
    /// "git didn't answer" preserved — see ``Resolution``.
    public static func resolve(at cwd: String) -> Resolution {
        // An empty cwd is settled, not transient: no session row ever grows one
        // later, so it is a permanent "no repository here" rather than a question
        // that might be answerable next launch.
        guard !cwd.isEmpty else { return .notAGitWorkingTree }
        guard FileManager.default.fileExists(atPath: cwd) else { return .undetermined }

        // Settle the "is there a repository here at all" question first, because it is
        // the only one git answers unambiguously. Inside a repo `--is-inside-work-tree`
        // exits 0 printing true/false; outside one it exits 128. Every other exit
        // status is git failing rather than git saying no.
        switch outcome(cwd: cwd, ["rev-parse", "--is-inside-work-tree"]) {
        case .output("true"):
            break
        case .output, .empty:
            // "false" — inside a `.git` directory, not a working tree.
            return .notAGitWorkingTree
        case .failed(let status):
            return status == 128 ? .notAGitWorkingTree : .undetermined
        }

        var current = cwd
        // Bounded climb: real submodule nesting is shallow; the cap guards against
        // a corrupt .gitmodules / on-disk symlink cycle that could otherwise make
        // `--show-superproject-working-tree` keep returning a non-empty path forever.
        var depth = 0
        while depth < 64 {
            switch outcome(cwd: current, ["rev-parse", "--show-superproject-working-tree"]) {
            case .output(let superproject):
                current = superproject
                depth += 1
            case .empty:
                // Not a submodule: the climb is over, and that is an answer.
                depth = 64
            case .failed:
                // Stopping here would report whatever level we happened to reach as
                // the root — a wrong answer, stamped permanently. Report none.
                return .undetermined
            }
        }
        // Prefer the repo's main working tree, which collapses linked worktrees. A
        // *failed* listing may not fall back to `--show-toplevel`: inside a linked
        // worktree that returns the worktree's own path, so the fallback would name
        // the worktree as the project — the very grouping this step exists to undo,
        // recorded permanently. Only a listing git actually produced is trusted.
        switch outcome(cwd: current, ["worktree", "list", "--porcelain"]) {
        case .output(let listing):
            if let main = firstWorktreePath(in: listing) { return .resolved(main) }
        case .empty:
            break
        case .failed:
            return .undetermined
        }
        if case .output(let toplevel) = outcome(cwd: current, ["rev-parse", "--show-toplevel"]) {
            return .resolved(toplevel)
        }
        return .undetermined
    }

    /// Returns the path of the repository's **main** working tree for `dir`
    /// (the first `worktree` entry of `git worktree list --porcelain`), or nil
    /// if `dir` isn't in a git repo. For a normal checkout this is the repo
    /// root; for a linked worktree it's the primary checkout the worktree
    /// belongs to — so all worktrees of a project resolve to one root.
    public static func mainWorkingTree(at dir: String) -> String? {
        guard let listing = output(cwd: dir, ["worktree", "list", "--porcelain"]) else { return nil }
        return firstWorktreePath(in: listing)
    }

    /// Runs `git -C <cwd> <args…>` and returns trimmed stdout, or nil when cwd
    /// is missing/empty, git exits non-zero, or the output is empty.
    public static func output(cwd: String, _ args: [String]) -> String? {
        guard case .output(let text) = outcome(cwd: cwd, args) else { return nil }
        return text
    }

    /// ``output(cwd:_:)``, reporting *why* there is no output — see ``Outcome``.
    public static func outcome(cwd: String, _ args: [String]) -> Outcome {
        guard !cwd.isEmpty,
              FileManager.default.fileExists(atPath: cwd) else { return .failed(status: -1) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["-C", cwd] + args
        let out = Pipe()
        proc.standardOutput = out
        // Discard stderr to /dev/null — we don't use it, and leaving it an
        // undrained Pipe risks deadlock if git writes more than the pipe buffer.
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            // Drain stdout to EOF *before* waiting: reading blocks until git closes
            // the pipe (i.e. exits), so a large output can't fill the buffer and
            // wedge a git that's blocked on write while we block in waitUntilExit().
            let data = out.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                return .failed(status: proc.terminationStatus)
            }
            let str = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return str.isEmpty ? .empty : .output(str)
        } catch {
            return .failed(status: -1)
        }
    }

    /// The first `worktree <path>` entry of `git worktree list --porcelain`, which
    /// git lists main-working-tree-first.
    private static func firstWorktreePath(in listing: String) -> String? {
        for line in listing.split(separator: "\n") where line.hasPrefix("worktree ") {
            let path = line.dropFirst("worktree ".count).trimmingCharacters(in: .whitespaces)
            return path.isEmpty ? nil : path
        }
        return nil
    }
}
