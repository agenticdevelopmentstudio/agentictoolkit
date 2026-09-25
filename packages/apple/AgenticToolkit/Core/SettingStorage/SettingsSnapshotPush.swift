import Foundation
import OSLog

/// Mirrors a group of settings into another process: on any change, at
/// startup, and on every reconnect, the whole idempotent snapshot is sent.
///
/// A full snapshot rather than a delta, so a receiver that was down for one of
/// the changes is corrected by the next push rather than staying
/// half-configured. A newer push supersedes one still retrying, so a stale body
/// can never land after a fresh one. The reconnect handler is registered once
/// per instance, and is inert while the push is stopped.
///
/// What the snapshot holds, how it is encoded and how it travels are the
/// caller's; the engine — observe, snapshot, supersede, bounded retry,
/// re-push on reconnect — is this one copy.
@MainActor
public final class SettingsSnapshotPush {

    /// Builds the body to send, or nil when it can't be built (logged, not sent).
    public typealias Snapshot = @MainActor () -> Data?
    /// Sends one body; true when the receiver took it.
    public typealias Send = @Sendable (Data) async -> Bool
    /// Registers a handler to run on every reconnect.
    public typealias RegisterReconnect = (@escaping @Sendable () -> Void) -> Void

    private let label: String
    private let logger: Logger
    private let snapshot: Snapshot
    private let sendBody: Send
    private let registerReconnect: RegisterReconnect
    private let backoffs: [UInt64]

    private var observers: [AnyObject] = []
    private var observing = false
    private var reconnectInstalled = false
    private var pushTask: Task<Void, Never>?

    /// - Parameters:
    ///   - label: names the channel in log lines ("Billing prefs").
    ///   - backoffs: nanoseconds to wait before each attempt; the default
    ///     tries at once, then after 0.5 s and 1.5 s.
    public init(
        label: String,
        logger: Logger,
        backoffs: [UInt64] = BoundedPush.defaultBackoffs,
        snapshot: @escaping Snapshot,
        send: @escaping Send,
        registerReconnect: @escaping RegisterReconnect
    ) {
        self.label = label
        self.logger = logger
        self.backoffs = backoffs
        self.snapshot = snapshot
        self.sendBody = send
        self.registerReconnect = registerReconnect
    }

    /// Whether the push is observing its settings.
    public var isObserving: Bool { observing }

    /// Observes `settings`, pushes the snapshot now, and re-pushes it on every
    /// reconnect. A repeat call while observing is ignored.
    public func start<Value: Codable & Sendable>(observing settings: [UserSetting<Value>]) {
        start(observers: settings.map { setting in
            UserSettingObserver(setting) { [weak self] _ in self?.push() }
        })
    }

    /// ``start(observing:)`` for settings of mixed types: `makeObservers` is
    /// handed the change handler and returns whatever observers it built,
    /// which this push keeps alive until ``stop()``.
    public func start(makeObservers: (_ onChange: @escaping @MainActor () -> Void) -> [AnyObject]) {
        start(observers: makeObservers { [weak self] in self?.push() })
    }

    private func start(observers built: [AnyObject]) {
        guard !observing else {
            logger.warning("\(self.label, privacy: .public) push started more than once; ignoring the repeat")
            return
        }
        observing = true
        observers = built
        // Observers fire only on change, and the receiver may have restarted.
        push()
        guard !reconnectInstalled else { return }
        reconnectInstalled = true
        registerReconnect { [weak self] in
            Task { @MainActor in
                guard let self, self.observing else { return }
                self.push()
            }
        }
    }

    /// Stops observing and cancels a push still retrying. The reconnect
    /// handler stays registered but does nothing until the next ``start``.
    public func stop() {
        observing = false
        observers = []
        pushTask?.cancel()
        pushTask = nil
    }

    /// Sends the current snapshot, superseding any push still retrying.
    public func push() {
        guard let body = snapshot() else {
            logger.error("Failed to build the \(self.label, privacy: .public) snapshot")
            return
        }
        pushTask?.cancel()
        let label = label, logger = logger, backoffs = backoffs, send = sendBody
        pushTask = Task {
            await BoundedPush.send(label: label, logger: logger, backoffs: backoffs) { await send(body) }
        }
    }

    /// Awaits the most recent push — for tests.
    public func awaitPendingPush() async {
        await pushTask?.value
    }

    /// `values` as sorted-key JSON, the byte-stable form a snapshot is sent in.
    public static func encodeSorted(_ values: some Encodable) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(values)
    }
}

/// A push retried a bounded number of times: try, then back off and retry,
/// stopping at once if a newer push cancelled this one. A dropped push leaves
/// the receiver on its last-known state until the next change re-pushes, so the
/// retry is deliberately bounded rather than infinite.
public enum BoundedPush {

    /// At once, then after 0.5 s, then after 1.5 s.
    public static let defaultBackoffs: [UInt64] = [0, 500_000_000, 1_500_000_000]

    /// - Parameters:
    ///   - label: names the channel in log lines.
    ///   - call: performs one push; true on success, false on a transport failure.
    public static func send(
        label: String,
        logger: Logger,
        backoffs: [UInt64] = defaultBackoffs,
        call: @Sendable () async -> Bool
    ) async {
        for (attempt, delay) in backoffs.enumerated() {
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            // Superseded: the stale body must not land after the newer one.
            if Task.isCancelled { return }
            if await call() { return }
            logger.warning("\(label, privacy: .public) push attempt \(attempt + 1) of \(backoffs.count) failed")
        }
        logger.error(
            "\(label, privacy: .public) push failed after \(backoffs.count) attempts; receiver keeps its prior state"
        )
    }
}
