// Core/Chat/FeedChatSession.swift
import Foundation

/// A read-only `ChatSession` that renders something already being said
/// elsewhere: a log, an activity feed, several conversations merged onto one
/// timeline. It never sends anything — the transcript is the whole of it.
///
/// This exists so a feed window is a `ChatView` rather than a bespoke list.
/// `ChatView` is bound to `AIChatViewModel(session:)`, so "host a feed in the
/// chat UI" is a session, not a second view hierarchy — and the composer, the
/// bubbles, the theming, the scroll-anchoring all come along already built.
///
/// The loader supplies the whole transcript each time rather than a delta. A
/// feed's rows are not the client's to accumulate — an entry can be reclassified
/// or filtered out between polls — so replacing the transcript wholesale is both
/// simpler and the only thing that stays correct. `ChatEvent.transcriptLoaded`
/// already means exactly that.
public final class FeedChatSession: ChatSession, @unchecked Sendable {

    /// Produces the transcript as it stands, oldest first. Returning nil means
    /// "couldn't read it" — the previous transcript is kept rather than being
    /// blanked, because a momentarily unreachable source is not an empty feed.
    public typealias Loader = @Sendable () async -> [ChatMessage]?

    private let load: Loader
    private let refreshInterval: Duration

    private let lock = NSLock()
    private var continuation: AsyncStream<ChatEvent>.Continuation?
    private var pump: Task<Void, Never>?

    /// - Parameters:
    ///   - refreshInterval: how often to re-read. A feed has no push channel, so
    ///     this is the whole of its liveness.
    ///   - load: reads the transcript.
    public init(refreshInterval: Duration = .seconds(5), load: @escaping Loader) {
        self.refreshInterval = refreshInterval
        self.load = load
    }

    public func events() -> AsyncStream<ChatEvent> {
        AsyncStream { continuation in
            withLock { self.continuation = continuation }
            continuation.onTermination = { [weak self] _ in self?.pump?.cancel() }
            start()
        }
    }

    /// Re-reads now, without waiting for the next interval. For a filter change
    /// or an explicit refresh — anything where waiting would look broken.
    public func refresh() { start() }

    /// No-op: a feed is something being watched, not something being talked to.
    /// The composer is left in the window and disabled rather than removed, so
    /// the shape of the thing stays honest about what it is.
    public func send(_ text: String) {}

    public func interrupt() {}

    public func close() {
        pump?.cancel()
        withLock { continuation }?.finish()
    }

    // MARK: - Pump

    /// Replaces the running poll rather than adding one, so a burst of
    /// `refresh()` calls (a filter toggled three times) leaves exactly one.
    private func start() {
        let existing = withLock { pump }
        existing?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let messages = await self.load()
                guard !Task.isCancelled else { return }
                let cont = self.withLock { self.continuation }
                guard let cont else { return }
                if let messages {
                    cont.yield(.transcriptLoaded(messages))
                }
                cont.yield(.stateChanged(.ready))
                try? await Task.sleep(for: self.refreshInterval)
            }
        }
        withLock { pump = task }
    }

    private func withLock<Value>(_ body: () -> Value) -> Value {
        lock.lock(); defer { lock.unlock() }; return body()
    }
}
