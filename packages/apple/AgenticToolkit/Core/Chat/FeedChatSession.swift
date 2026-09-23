// Core/Chat/FeedChatSession.swift
import Foundation

/// A `ChatSession` over something already being said elsewhere: a log, an
/// activity feed, several conversations merged onto one timeline.
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
///
/// It can also be *written to*, where the host supplies a ``Sender``. That is a
/// different shape from an ordinary chat: what is typed here does not enter the
/// transcript, it enters whatever the transcript is a record of, and comes back
/// round only when that record is next read. The gap is seconds, so the message
/// is held in front of the transcript as pending until the source says it back
/// — and if it never does, it is marked failed rather than left looking sent.
public final class FeedChatSession: ChatSession, @unchecked Sendable {

    /// Produces the transcript as it stands, oldest first. Returning nil means
    /// "couldn't read it" — the previous transcript is kept rather than being
    /// blanked, because a momentarily unreachable source is not an empty feed.
    public typealias Loader = @Sendable () async -> [ChatMessage]?

    /// Writes a line into whatever the feed is reading. Returns nil when the
    /// line was handed over, or the reason it could not be — which the reader
    /// sees under the message they typed.
    ///
    /// "Handed over" is deliberately weaker than "arrived": the source is
    /// something else's to write, so the only proof of arrival is reading it
    /// back, which is what ``ChatMessage/Delivery/sending`` waits for.
    ///
    /// The second argument is the ``destinationID`` as it stood when the line
    /// was typed — not as it stands when the write gets round to running. The
    /// write is asynchronous, and a reader who moves to another conversation in
    /// between would otherwise have the line typed into the first one delivered
    /// to the second.
    public typealias Sender = @Sendable (_ text: String, _ destinationID: String?) async -> String?

    private let load: Loader
    private let send: Sender?
    private let refreshInterval: Duration
    private let sendTimeout: Duration

    private let lock = NSLock()
    private var sendable: Bool
    private var continuation: AsyncStream<ChatEvent>.Continuation?
    private var pump: Task<Void, Never>?

    /// The last transcript read, and the messages written since that are not in
    /// it yet. What the view sees is the two, in that order.
    private var loaded: [ChatMessage] = []
    private var pending: [ChatMessage] = []
    private var destination: String?
    /// Which conversation each pending line was written to, by id. Kept beside
    /// the message rather than on it, because a line written to a conversation
    /// with nothing on screen yet has no attribution to borrow and still has a
    /// destination.
    private var destinations: [String: String] = [:]
    private var timeouts: [String: Task<Void, Never>] = [:]

    /// - Parameters:
    ///   - refreshInterval: how often to re-read. A feed has no push channel, so
    ///     this is the whole of its liveness.
    ///   - sendTimeout: how long a written line waits to be read back before it
    ///     is called failed. Generous by chat standards because the round trip
    ///     is not a network one: an agent that is mid-turn when the line arrives
    ///     answers it when it is finished, not when it is sent.
    ///   - send: writes a line into the source. Nil for a feed that is only
    ///     watched, which is what leaves the composer disabled.
    ///   - initial: the transcript to stand on until the first read returns.
    ///     Without it the session's idea of the transcript is empty, and the
    ///     first thing that publishes — a line typed before the first poll
    ///     landed — yields *only* that line, wiping whatever the host had
    ///     already put on screen.
    ///   - load: reads the transcript.
    public init(
        refreshInterval: Duration = .seconds(5),
        sendTimeout: Duration = .seconds(60),
        send: Sender? = nil,
        initial: [ChatMessage] = [],
        load: @escaping Loader
    ) {
        self.refreshInterval = refreshInterval
        self.sendTimeout = sendTimeout
        self.send = send
        self.sendable = send != nil
        self.loaded = initial
        self.load = load
    }

    /// Whether anything typed here has somewhere to go.
    ///
    /// Starts as "there is a sender" and stays that way for a session whose
    /// destination is fixed. It is settable because a feed's destination can
    /// come and go under it: the Conversations window has exactly one session to
    /// write to in single-conversation mode and none in multi, and it is the
    /// same session object either way. Setting it never conjures a sender — with
    /// none supplied, ``send(_:)`` still has nowhere to write.
    public var canSend: Bool {
        get { withLock { sendable && send != nil } }
        set { withLock { sendable = newValue } }
    }

    /// The conversation a line typed here goes to, by
    /// ``ChatMessage/Attribution/sourceID`` — nil for a feed with one fixed
    /// destination, where the question never comes up.
    ///
    /// A feed that can be pointed at different conversations has to know which
    /// one each written line belongs to, or the line follows the reader around:
    /// typed into one conversation, it is drawn in front of every other one the
    /// window is moved to, and — since the others never say it back — it sits
    /// there until it goes red. With a destination, a pending line is shown only
    /// while its conversation is on the timeline and is only settled by a line
    /// that conversation recorded.
    public var destinationID: String? {
        get { withLock { destination } }
        set {
            let changed = withLock { () -> Bool in
                guard destination != newValue else { return false }
                destination = newValue
                // A failed line has been read by now: it was on screen, in red,
                // for as long as the reader stayed. Moving on is the reader
                // dismissing it — keeping it would pin it under the transcript
                // for the life of the window.
                dropFailed()
                return true
            }
            if changed { publish() }
        }
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

    /// Writes `text` into the source, and shows it here as pending until the
    /// source reads back.
    ///
    /// The message is shown before the write is attempted, not after it
    /// succeeds: the write is a round trip through another application, and a
    /// composer that empties into nothing for a second reads as a dropped
    /// keystroke. A write that fails turns the same bubble into a failed one,
    /// which is a stronger thing to see than a message that was never drawn.
    public func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canSend, let send else { return }

        let target = withLock { destination }
        let message = ChatMessage(
            id: "pending-\(UUID().uuidString)",
            role: .user,
            text: trimmed,
            // Borrowed from the conversation it is joining, so a written line is
            // headed by the same session as everything around it rather than
            // appearing as a row from nowhere.
            attribution: withLock {
                guard let target else { return loaded.last?.attribution }
                return loaded.last { $0.attribution?.sourceID == target }?.attribution
            },
            delivery: .sending
        )
        withLock {
            // A new line to the same place supersedes an earlier failure there:
            // the reader has seen it and is trying again. Without this every
            // retry adds another red line and none of them ever leaves.
            dropFailed { destinations[$0.id] == target }
            pending.append(message)
            if let target { destinations[message.id] = target }
        }
        publish()

        let id = message.id
        withLock {
            timeouts[id] = Task { [weak self] in
                try? await Task.sleep(for: self?.sendTimeout ?? .seconds(60))
                guard !Task.isCancelled else { return }
                self?.fail(id, reason: "No answer yet — the session may not have taken it.")
            }
        }
        Task { [weak self] in
            if let reason = await send(trimmed, target) {
                self?.fail(id, reason: reason)
            }
        }
    }

    public func interrupt() {}

    public func close() {
        pump?.cancel()
        withLock {
            timeouts.values.forEach { $0.cancel() }
            timeouts.removeAll()
            destinations.removeAll()
            pending.removeAll()
        }
        withLock { continuation }?.finish()
    }

    // MARK: - Pending writes

    /// Removes the failed lines `matching` — every failed line by default.
    /// Called with the lock held.
    private func dropFailed(where matching: (ChatMessage) -> Bool = { _ in true }) {
        pending.removeAll { message in
            guard case .failed = message.delivery, matching(message) else { return false }
            destinations.removeValue(forKey: message.id)
            return true
        }
    }

    /// Marks a written line failed, unless the source has already said it back.
    private func fail(_ id: String, reason: String) {
        let changed = withLock { () -> Bool in
            guard let index = pending.firstIndex(where: { $0.id == id }) else { return false }
            timeouts.removeValue(forKey: id)?.cancel()
            pending[index].delivery = .failed(reason)
            return true
        }
        if changed { publish() }
    }

    /// Drops the written lines the source has now read back.
    ///
    /// Matched on text rather than on id because the two are different
    /// messages: one was typed here, the other was recorded over there, and
    /// nothing carries an identifier across a terminal. The timestamp is what
    /// keeps an identical line sent an hour ago from answering for this one —
    /// with a few seconds of slack, because the two clocks are not the same one.
    ///
    /// A line that was already given up on is reconciled too. A slow session
    /// answers after the timeout has marked its line failed, and leaving the
    /// pending copy in place then shows the reader the same sentence twice —
    /// once in red saying it never arrived, once underneath it having arrived.
    /// Arrival is the later fact and it wins.
    private func reconcile(_ transcript: [ChatMessage]) {
        withLock {
            pending.removeAll { message in
                let written = Self.normalized(message.text)
                let target = destinations[message.id]
                let arrived = transcript.contains { candidate in
                    candidate.role == .user
                        && (target == nil || candidate.attribution?.sourceID == target)
                        && Self.normalized(candidate.text) == written
                        && candidate.timestamp >= message.timestamp.addingTimeInterval(-Self.clockSlack)
                }
                if arrived {
                    timeouts.removeValue(forKey: message.id)?.cancel()
                    destinations.removeValue(forKey: message.id)
                }
                return arrived
            }
        }
    }

    /// The form two copies of the same line are compared in.
    ///
    /// What reaches the source is not always character-for-character what was
    /// typed: a terminal takes one line, so a pasted paragraph arrives with its
    /// breaks flattened to spaces. Comparing on runs of whitespace collapsed to
    /// one keeps that the same message — the alternative is a line that is
    /// visibly in the transcript and still shown as pending until it times out.
    public static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// How far a source's clock may run behind this one before a line read back
    /// stops being recognised as the line that was just written.
    private static let clockSlack: TimeInterval = 5

    /// Re-publishes the transcript as it now stands: what was read, then what
    /// has been written since and not read back — those of it whose
    /// conversation is on the timeline.
    ///
    /// "On the timeline" is the conversation the composer points at, or any
    /// conversation the transcript holds a line of. The second is what keeps a
    /// line typed in one conversation visible when the reader widens the window
    /// to several that include it; the first is what shows it at all in a
    /// conversation that has nothing on screen yet.
    private func publish() {
        let (transcript, cont) = withLock { () -> ([ChatMessage], AsyncStream<ChatEvent>.Continuation?) in
            let shown = Set(loaded.compactMap { $0.attribution?.sourceID })
            let visible = pending.filter { message in
                guard let target = destinations[message.id] else { return true }
                return target == destination || shown.contains(target)
            }
            return (loaded + visible, continuation)
        }
        cont?.yield(.transcriptLoaded(transcript))
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
                    self.reconcile(messages)
                    self.withLock { self.loaded = messages }
                    self.publish()
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
