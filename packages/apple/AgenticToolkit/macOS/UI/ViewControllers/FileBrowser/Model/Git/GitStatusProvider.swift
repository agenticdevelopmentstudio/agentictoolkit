import AgenticToolkitCore
import Foundation
import os

/// Asks `GitClient` for the working tree status of one repository and hands
/// the result to the file browser on the main thread. A newer refresh
/// supersedes an older one still in flight.
public final class GitStatusProvider: Sendable {
    public let repoRoot: URL

    private let client: GitClient
    private let requestID = OSAllocatedUnfairLock<UUID?>(initialState: nil)

    public init(repoRoot: URL, client: GitClient = .shared) {
        self.repoRoot = repoRoot
        self.client = client
    }

    public func refresh(
        completion: @escaping @Sendable (
            _ fileStatuses: [String: GitFileStatus],
            _ dirStatuses: [String: GitFileStatus]
        ) -> Void
    ) {
        let id = UUID()
        requestID.withLock { $0 = id }
        let client = self.client
        let repoRoot = self.repoRoot
        Task {
            let status: GitStatus
            do {
                status = try await client.status(in: repoRoot)
                let fileCount = status.files.count
                let dirCount = status.directories.count
                Self.logger.info(
                    "Git status: \(fileCount, privacy: .public) files, \(dirCount, privacy: .public) directories"
                )
            } catch is CancellationError {
                // Defensive, and unreachable as written: the `Task` above is
                // unstructured and its handle is discarded, so nothing holds a
                // reference that could cancel it. It states the policy anyway,
                // because the day someone keeps that handle, cancellation must
                // not read as a status failure — leave whatever was last
                // delivered in place rather than clobbering it with an empty
                // result.
                return
            } catch {
                // Never `error.localizedDescription`: for `GitClientError`,
                // that interpolates git's own `standardError`, and the
                // branch's logging rule is that OSLog records what was
                // called, never what git said. `logDescription` carries only
                // the case name and structured fields (verb, exit status).
                let path = repoRoot.path
                let reason = (error as? GitClientError)?.logDescription ?? String(describing: type(of: error))
                Self.logger.error("Git status failed for \(path, privacy: .public): \(reason, privacy: .public)")
                status = .empty
            }
            guard self.requestID.withLock({ $0 == id }) else { return }
            await MainActor.run {
                guard self.requestID.withLock({ $0 == id }) else { return }
                completion(status.files, status.directories)
            }
        }
    }
}

extension GitStatusProvider: Loggable {
    public static nonisolated let logger = makeLogger()
}
