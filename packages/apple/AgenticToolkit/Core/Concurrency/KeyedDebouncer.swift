import Foundation

/// One debounced unit of work per key, with the guarantee that scheduled work
/// is never silently forgotten.
///
/// Three hand-copies of this existed before it — `NotesManager`'s
/// `scheduleSave`/`flushPendingSaves`, `TextDocumentSaveScheduler`'s
/// (which its own doc comment described as a copy of the first), and the
/// one-shot variant in `SemanticTokenHighlightProvider` — each a dictionary of
/// per-key `Task`s, cancel-and-reschedule on every touch, and a flush that
/// cancels everyone, awaits each task and only then writes once per key. They
/// were structurally identical and independently wrong in the same place, so
/// this is the extraction rather than a fourth copy.
///
/// **The invariant that makes this more than deduplication.** An entry leaves
/// this debouncer on exactly two events: its work completed *without
/// throwing*, or a caller explicitly `cancel`led it. Failure keeps the entry
/// and re-arms it with backoff. The copies this replaces removed the entry
/// *before* attempting the work and only logged on failure, so a save that hit
/// a full disk or a revoked network volume left nothing pending, nothing
/// armed, and a later `flushAll()` that reported success over an empty map —
/// the user's edit gone with an os_log line as the only evidence.
///
/// **Never more than one run per key at a time.** `schedule` during a run does
/// not start a second one; it records the newer work, and the finishing run
/// re-arms for it. `flush(key:)` awaits a run already in flight rather than
/// racing it with a second. That matters wherever the work is a write to a
/// destination named by the key, which is every current caller.
///
/// Foundation-only and `@MainActor`, like the call sites it serves: the work
/// closures read main-actor state (a `Note`, a `TextDocument`) to decide what
/// to persist. The closure is `async`, so the work itself is free to leave the
/// main actor — and should, if it touches a disk.
@MainActor
public final class KeyedDebouncer<Key: Hashable & Sendable> {

    /// One unit of debounced work. Throwing means "this did not happen" — the
    /// entry stays pending and is retried; see the type comment.
    public typealias Work = @MainActor () async throws -> Void

    private struct Entry {
        /// The most recently scheduled work for this key.
        var work: Work

        /// Bumped by every `schedule`, so a run that started against older
        /// work can tell it has been superseded and must not retire the entry.
        var generation: Int

        /// The armed delay, or `nil` while the work is running.
        var timer: Task<Void, Never>?

        /// The run in flight, or `nil` when nothing is running.
        var run: Task<Void, Never>?

        /// Consecutive failures for this key, driving the retry backoff.
        var failures: Int
    }

    private let debounce: Duration
    private let maximumRetryInterval: Duration
    private let onFailure: (@MainActor (Key, any Error) -> Void)?

    private var entries: [Key: Entry] = [:]

    /// - Parameters:
    ///   - debounce: How long a key stays quiet before its work runs.
    ///   - maximumRetryInterval: Ceiling on the exponential backoff applied
    ///     after a failure. A permanently failing write retries at this
    ///     interval forever rather than giving up, because giving up is what
    ///     loses the work — the entry has to still be there for `flushAll()`
    ///     at termination to find.
    ///   - onFailure: Called once per failed attempt, with the key and the
    ///     error. The debouncer itself never logs; whoever owns the work owns
    ///     how a failure is reported.
    public init(
        debounce: Duration = .seconds(1),
        maximumRetryInterval: Duration = .seconds(30),
        onFailure: (@MainActor (Key, any Error) -> Void)? = nil
    ) {
        self.debounce = debounce
        self.maximumRetryInterval = max(debounce, maximumRetryInterval)
        self.onFailure = onFailure
    }

    // MARK: - Scheduling

    /// Schedules `work` for `key`, replacing whatever was scheduled before it
    /// and restarting the debounce window.
    public func schedule(key: Key, _ work: @escaping Work) {
        if var entry = entries[key] {
            entry.work = work
            entry.generation &+= 1
            entry.failures = 0
            entries[key] = entry
        } else {
            entries[key] = Entry(work: work, generation: 0, timer: nil, run: nil, failures: 0)
        }

        // A run already in flight is left alone: cancelling it would not stop
        // the work it is awaiting, only the bookkeeping that follows it. It
        // will see the bumped generation when it finishes and re-arm for the
        // newer work itself.
        guard entries[key]?.run == nil else {
            entries[key]?.timer?.cancel()
            entries[key]?.timer = nil
            return
        }
        armTimer(key: key, after: debounce)
    }

    /// Drops `key`'s pending work without running it.
    ///
    /// The only way, other than success, that an entry leaves this debouncer —
    /// so it is the caller's explicit statement that the work is no longer
    /// wanted, not a way to recover from a failure.
    public func cancel(key: Key) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        entry.timer?.cancel()
        entry.run?.cancel()
    }

    /// Drops every pending entry without running any of it.
    public func cancelAll() {
        for key in entries.keys {
            cancel(key: key)
        }
    }

    // MARK: - Flushing

    /// Runs `key`'s pending work now rather than when its debounce elapses,
    /// and returns once it has been attempted.
    ///
    /// Never starts a second run beside one already in flight — it awaits that
    /// one instead. If the work throws, the entry stays pending (with a
    /// re-armed backoff) exactly as it would from the timer path; a caller
    /// that needs to know reads `isPending(key:)` afterwards.
    public func flush(key: Key) async {
        if let run = entries[key]?.run {
            await run.value
        }
        guard entries[key] != nil else { return }

        entries[key]?.timer?.cancel()
        entries[key]?.timer = nil

        // Something else may have started a run while the await above was
        // suspended. One run per key, so let that one be the flush.
        if let run = entries[key]?.run {
            await run.value
            return
        }

        beginRun(key: key)
        if let run = entries[key]?.run {
            await run.value
        }
    }

    /// Runs every pending entry now, one key at a time, and returns the keys
    /// whose work still failed.
    ///
    /// Sequential rather than concurrent because the copies this replaces were
    /// sequential and their work writes to a shared destination; nothing here
    /// needs the parallelism, and serialising keeps a failure attributable.
    @discardableResult
    public func flushAll() async -> [Key] {
        for key in Array(entries.keys) {
            await flush(key: key)
        }
        return Array(entries.keys)
    }

    // MARK: - Inspection

    /// The keys with work still pending — scheduled, running, or awaiting a
    /// retry after a failure.
    public var pendingKeys: [Key] {
        Array(entries.keys)
    }

    public func isPending(key: Key) -> Bool {
        entries[key] != nil
    }

    // MARK: - Private

    private func armTimer(key: Key, after delay: Duration) {
        guard entries[key] != nil else { return }
        entries[key]?.timer?.cancel()
        entries[key]?.timer = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return // cancelled: a newer schedule, a cancel, or a flush
            }
            guard !Task.isCancelled, let self else { return }
            self.beginRun(key: key)
        }
    }

    private func beginRun(key: Key) {
        guard let entry = entries[key], entry.run == nil else { return }
        entries[key]?.timer?.cancel()
        entries[key]?.timer = nil

        let generation = entry.generation
        let work = entry.work
        // Assigned before the task body can run: `Task { }` from a main-actor
        // context is enqueued, not entered, so `entries[key]?.run` is set by
        // the time anything inside the closure observes it.
        entries[key]?.run = Task { [weak self] in
            guard let self else { return }
            do {
                try await work()
                self.finishRun(key: key, generation: generation, error: nil)
            } catch {
                self.finishRun(key: key, generation: generation, error: error)
            }
        }
    }

    private func finishRun(key: Key, generation: Int, error: (any Error)?) {
        if let error {
            onFailure?(key, error)
        }

        // Gone means `cancel(key:)` ran while the work was suspended. The
        // caller said drop it; do not resurrect it.
        guard var entry = entries[key] else { return }
        entry.run = nil

        let superseded = entry.generation != generation
        if error == nil && !superseded {
            entries.removeValue(forKey: key)
            return
        }

        if superseded {
            // Newer work arrived while this one ran. Whether this attempt
            // succeeded says nothing about the newer work, so the failure
            // count starts over and it gets a normal debounce window.
            entry.failures = 0
            entries[key] = entry
            armTimer(key: key, after: debounce)
            return
        }

        entry.failures &+= 1
        entries[key] = entry
        armTimer(key: key, after: retryInterval(afterFailures: entry.failures))
    }

    /// Exponential backoff from `debounce`, capped at `maximumRetryInterval`.
    /// The shift is capped independently so the multiplication cannot
    /// overflow for a long-lived entry that keeps failing.
    private func retryInterval(afterFailures failures: Int) -> Duration {
        let shift = min(max(failures - 1, 0), 20)
        let scaled = debounce * (1 << shift)
        return min(scaled, maximumRetryInterval)
    }
}
