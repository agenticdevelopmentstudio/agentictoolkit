import Foundation

/// Runs an owner's refresh at once, then every `interval`, until stopped or
/// until the owner is freed.
///
/// The poll loop of every model that mirrors a daemon's state. One copy, so a
/// change to how polling behaves — backing off, a refresh on demand — is made
/// once. The owner is held weakly: a model nobody keeps is freed without a
/// `stop()`, and its loop ends at the next tick.
@MainActor
public final class PeriodicRefresher {

    /// Seconds between refreshes, measured from the end of one to the start
    /// of the next, so a slow refresh never overlaps itself.
    public let interval: TimeInterval

    private var task: Task<Void, Never>?

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    /// Whether a loop is running.
    public var isRunning: Bool { task != nil }

    /// Starts the loop, replacing any running one: `body(owner)` now, then
    /// every ``interval``.
    public func start<Owner: AnyObject>(
        for owner: Owner,
        _ body: @escaping @MainActor (Owner) async -> Void
    ) {
        stop()
        let interval = interval
        task = Task { @MainActor [weak owner] in
            if let owner { await body(owner) }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let owner else { break }
                await body(owner)
            }
        }
    }

    /// Ends the loop. A refresh already under way finishes; no other starts.
    public func stop() {
        task?.cancel()
        task = nil
    }
}
