import Foundation

/// Everything `GitClient` can fail with. Deliberately three cases and no more:
/// a caller either could not reach git at all, ran out of time, or got a
/// non-zero exit.
public enum GitClientError: Error, LocalizedError, Equatable {
    /// git ran and exited non-zero. `standardError` is what it complained
    /// about, carried here for a caller to show — it is never written to the
    /// command log.
    case commandFailed(verb: String, exitStatus: Int32, standardError: String)
    /// The invocation outlived `GitClientConfiguration.timeout`, or could not
    /// be launched at all. The child is terminated before this is thrown.
    case timedOut(verb: String)
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
        case let .executableNotFound(path):
            return "No git executable at \(path). Change it in Settings > Git."
        }
    }
}
