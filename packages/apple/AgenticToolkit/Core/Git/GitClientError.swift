import Foundation

/// Everything `GitClient` can fail with.
///
/// Four cases, and the split between them is about *how far the invocation
/// got*, because that is what a caller can act on: nothing executable to run,
/// a process that never produced an exit status, a process that ran out of
/// time, or a process that ran and disagreed.
///
/// One error deliberately does **not** appear here: `CancellationError` leaves
/// `GitClient` as itself, unwrapped. See `GitClient.execute`.
public enum GitClientError: Error, LocalizedError, Equatable {
    /// git ran to completion and exited non-zero. `standardError` is what it
    /// complained about, carried here for a caller to show — it is never
    /// written to the command log.
    ///
    /// This case means *only* that: a real exit status, produced by git. An
    /// invocation that never got that far is `.launchFailed`.
    case commandFailed(verb: String, exitStatus: Int32, standardError: String)
    /// The invocation outlived `GitClientConfiguration.timeout`. The child is
    /// terminated before this is thrown.
    case timedOut(verb: String)
    /// The invocation produced no exit status at all: the child could not be
    /// spawned (most often a working directory that does not exist), or the
    /// channel carrying its output failed. `reason` is the underlying error's
    /// description, for a human reading a bug report.
    case launchFailed(verb: String, reason: String)
    /// Nothing executable at the configured path; no process was spawned.
    case executableNotFound(path: String)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(verb, exitStatus, standardError):
            let detail = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "git \(verb) exited with status \(exitStatus)."
                : "git \(verb) exited with status \(exitStatus): \(detail)"
        case let .timedOut(verb):
            return "git \(verb) did not finish within the configured timeout."
        case let .launchFailed(verb, reason):
            return "git \(verb) could not be run: \(reason)"
        case let .executableNotFound(path):
            return "No git executable at \(path). Change it in Settings > Git."
        }
    }

    /// A description safe to hand to `OSLog`: the case name plus whatever
    /// structured fields exist (verb, exit status), and **never**
    /// `standardError` — that is git's own output, and the branch's logging
    /// rule is that OSLog records what was called, never what git said.
    /// `errorDescription` is unsafe for logging for exactly this reason: it
    /// interpolates `standardError` for `.commandFailed`.
    public var logDescription: String {
        switch self {
        case let .commandFailed(verb, exitStatus, _):
            return "commandFailed(verb: \(verb), exitStatus: \(exitStatus))"
        case let .timedOut(verb):
            return "timedOut(verb: \(verb))"
        case let .launchFailed(verb, _):
            return "launchFailed(verb: \(verb))"
        case .executableNotFound:
            return "executableNotFound"
        }
    }
}
