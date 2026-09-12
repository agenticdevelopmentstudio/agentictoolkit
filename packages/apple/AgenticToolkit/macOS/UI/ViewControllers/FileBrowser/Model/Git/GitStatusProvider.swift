import AgenticToolkitCore
import Foundation
import os

/// What one `git status` run learned about a checkout.
///
/// The failure case is spelled rather than swallowed. "We could not ask git"
/// and "the tree is clean" are different facts that an empty `GitStatus`
/// cannot tell apart, and a consumer that cleared its badges on the former
/// repainted every modified file as unmodified because git was misconfigured
/// or timed out. Saying `unavailable` out loud puts that decision where the
/// consumer can see it (`explicit-over-implicit`) instead of hiding it in an
/// early `return` inside the provider.
public enum GitStatusRefreshResult: Sendable {
    case status(GitStatus)
    case unavailable
}

/// A registration with a `GitStatusProvider`. Hold it for as long as you want
/// the results; releasing it unregisters. Modelled as a token rather than an
/// `addObserver`/`removeObserver` pair so a consumer cannot forget the second
/// half — the compiler's lifetime rules do the unregistering.
public final class GitStatusObservation: Sendable {
    private let cancel: @Sendable () -> Void

    init(cancel: @escaping @Sendable () -> Void) {
        self.cancel = cancel
    }

    deinit { cancel() }
}

/// Asks `GitClient` for the working tree status of one repository and hands
/// the result to everyone watching that checkout, on the main thread.
///
/// One provider serves every pane of a checkout, so results are **broadcast**
/// rather than returned to whoever asked. The provider used to keep a single
/// "latest request" id and drop the answer to any older one: correct when each
/// pane owned its own provider, and wrong the moment they shared one, because
/// two panes refreshing at once meant one of them was silently never told.
/// Now a request is a request for *everyone's* badges to be brought up to
/// date, and any component can ask — a file browser after an FSEvents burst,
/// the `Refresh Status` command from a pane's menu — without needing to know
/// who else is listening.
///
/// Overlapping requests coalesce into at most one queued follow-up run. A run
/// already in flight started before the request that arrived during it, so it
/// cannot be the answer to that request; one trailing run serves every such
/// caller, and a burst of N requests costs two git processes rather than N.
public final class GitStatusProvider: Sendable {
    /// Results are delivered on the main actor, so the observer is spelled
    /// `@MainActor` and a consumer never has to assert that for itself.
    public typealias Observer = @MainActor @Sendable (GitStatusRefreshResult) -> Void

    public let repoRoot: URL

    private let client: GitClient
    private let state = OSAllocatedUnfairLock<State>(initialState: State())

    private struct State: Sendable {
        var observers: [UUID: Observer] = [:]
        /// A `git status` is running now.
        var isRunning = false
        /// Someone asked while that run was in flight, so one more run is owed.
        var isQueued = false
    }

    public init(repoRoot: URL, client: GitClient = .shared) {
        self.repoRoot = repoRoot
        self.client = client
    }

    /// Registers `observer` for every result this provider produces from now
    /// on, delivered on the main actor. The returned token is the registration:
    /// keep it alive, and drop it to stop observing.
    public func observe(_ observer: @escaping Observer) -> GitStatusObservation {
        let id = UUID()
        state.withLock { $0.observers[id] = observer }
        return GitStatusObservation { [weak self] in
            self?.state.withLock { $0.observers[id] = nil }
        }
    }

    /// Asks git for this checkout's status and broadcasts the result.
    public func refresh() {
        let shouldStart = state.withLock { state -> Bool in
            guard !state.isRunning else {
                state.isQueued = true
                return false
            }
            state.isRunning = true
            return true
        }
        if shouldStart { start() }
    }

    private func start() {
        let client = self.client
        let repoRoot = self.repoRoot
        Task {
            let result = await Self.load(client: client, repoRoot: repoRoot)
            let observers = self.state.withLock { Array($0.observers.values) }
            await MainActor.run {
                for observer in observers {
                    observer(result)
                }
            }
            let runAgain = self.state.withLock { state -> Bool in
                if state.isQueued {
                    state.isQueued = false
                    return true
                }
                state.isRunning = false
                return false
            }
            if runAgain { self.start() }
        }
    }

    private static func load(client: GitClient, repoRoot: URL) async -> GitStatusRefreshResult {
        do {
            let status = try await client.status(in: repoRoot)
            let fileCount = status.files.count
            let dirCount = status.directories.count
            logger.info(
                "Git status: \(fileCount, privacy: .public) files, \(dirCount, privacy: .public) directories"
            )
            return .status(status)
        } catch is CancellationError {
            // Cancellation is not a status failure. It is reported the same
            // way a failure is — as "we do not know" — because the one thing
            // it is certainly not is evidence that the tree is clean.
            return .unavailable
        } catch {
            // Never `error.localizedDescription`: for `GitClientError`, that
            // interpolates git's own `standardError`, and the branch's logging
            // rule is that OSLog records what was called, never what git said.
            // `logDescription` carries only the case name and structured
            // fields (verb, exit status).
            let path = repoRoot.path
            let reason = (error as? GitClientError)?.logDescription ?? String(describing: type(of: error))
            logger.error("Git status failed for \(path, privacy: .public): \(reason, privacy: .public)")
            return .unavailable
        }
    }
}

extension GitStatusProvider: Loggable {
    public static nonisolated let logger = makeLogger()
}
