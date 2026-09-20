// Core/Chat/ConversationsSessionFilter.swift
import Foundation

/// Which of the observed sessions a merged feed shows, and the roster of the
/// ones it could show.
///
/// A merged feed is several conversations on one timeline, and the only thing
/// telling them apart is each message's ``ChatMessage/Attribution``. So the
/// roster is not configured, it is *read*: whoever appears in the page is on the
/// list, and a shelf beside the feed is drawing that list rather than a
/// subscription the host had to set up.
///
/// What is stored is the **hidden** set, never the shown one. That is the whole
/// reason a session that starts talking mid-session appears with its box already
/// ticked: nothing has hidden it, so it shows, and no bookkeeping runs when it
/// arrives. Storing the shown set would need a "have I seen this before" pass on
/// every page just to keep the default right.
///
/// `@unchecked Sendable` and lock-guarded because the two sides genuinely are
/// different threads: the shelf sets the hidden set on the main actor, and the
/// feed's poll reads it from inside a loader that should not have to await
/// anything. The lock covers two small values; there is no contention to speak
/// of.
public final class ConversationsSessionFilter: @unchecked Sendable {

    /// One observed session, as the feed describes it.
    public struct Session: Sendable, Equatable, Identifiable {
        /// ``ChatMessage/Attribution/sourceID`` — what the host resolves back to
        /// a real session.
        public let id: String
        /// The session's own name, or its id where it has not got one. Never
        /// empty: a blank row in the shelf is unclickable in practice.
        public let name: String
        /// The project and branch crumbs, in the order the feed gave them.
        public let context: [String]

        public init(id: String, name: String, context: [String]) {
            self.id = id
            self.name = name.isEmpty ? id : name
            self.context = context
        }

        /// What the shelf draws as the row's title: **where** the session is
        /// rather than what it is called — `project >> branch`.
        ///
        /// A session's own name is a summary of what it happens to be doing
        /// this minute ("editing AccountQuotaStore"), which changes under the
        /// reader while they are trying to find a row again. Its project and
        /// branch do not, and they are also how the reader thinks of it. The
        /// name is still drawn, underneath, and still searchable.
        ///
        /// Falls back to the name when there are no crumbs, because a row with
        /// a blank title is unclickable in practice.
        public var displayName: String {
            context.isEmpty ? name : context.joined(separator: " >> ")
        }

        /// What a textual filter matches against — everything the row draws, so
        /// typing a branch name finds the session on that branch even though
        /// the branch is not its name.
        public var searchText: String {
            ([name] + context).joined(separator: " ")
        }
    }

    /// Fired when the set of sessions in the feed changes — a new one starts
    /// talking, an old one falls off the end of the page. Called from whatever
    /// thread read the page, so a UI listener hops to the main actor itself.
    ///
    /// Not fired when only the *messages* change, which is most polls: the
    /// shelf would otherwise rebuild its table every few seconds and lose the
    /// reader's scroll position for nothing.
    public var onRosterChanged: (@Sendable ([Session]) -> Void)?

    private let lock = NSLock()
    private var hiddenIDs: Set<String> = []
    private var currentRoster: [Session] = []

    public init() {}

    /// The sessions the feed is currently not drawing.
    public var hidden: Set<String> {
        get { withLock { hiddenIDs } }
        set { withLock { hiddenIDs = newValue } }
    }

    /// The sessions seen in the last page read, in the order they first spoke.
    public var roster: [Session] { withLock { currentRoster } }

    /// Whether `id` is drawn — that is, whether the shelf shows its checkmark.
    public func isShown(_ id: String) -> Bool { !withLock { hiddenIDs.contains(id) } }

    /// Notes what a freshly read page contains and drops the hidden sessions
    /// from it.
    ///
    /// The roster is taken **before** the filter runs, which is what keeps a
    /// session on the shelf after you untick it — a roster read from the
    /// filtered result would delete the row that is the only way to get the
    /// session back.
    public func apply(to messages: [ChatMessage]) -> [ChatMessage] {
        let roster = Self.roster(of: messages)
        let changed: [Session]? = withLock {
            guard roster != currentRoster else { return nil }
            currentRoster = roster
            return roster
        }
        if let changed { onRosterChanged?(changed) }

        let hidden = withLock { hiddenIDs }
        guard !hidden.isEmpty else { return messages }
        return messages.filter { message in
            // A message with no session behind it — a notice the window itself
            // wrote — belongs to no row in the shelf, so no row can hide it.
            guard let id = message.attribution?.sourceID, !id.isEmpty else { return true }
            return !hidden.contains(id)
        }
    }

    /// The distinct sessions in a page, in the order they first appear.
    ///
    /// First appearance rather than alphabetical because this is the roster, not
    /// the display order: the shelf sorts it, and an order that changes under a
    /// sort the reader chose is not an order at all.
    static func roster(of messages: [ChatMessage]) -> [Session] {
        var seen = Set<String>()
        var result: [Session] = []
        for message in messages {
            guard let attribution = message.attribution,
                  !attribution.sourceID.isEmpty,
                  seen.insert(attribution.sourceID).inserted
            else { continue }
            result.append(Session(
                id: attribution.sourceID,
                name: attribution.name,
                context: attribution.context))
        }
        return result
    }

    private func withLock<Value>(_ body: () -> Value) -> Value {
        lock.lock(); defer { lock.unlock() }; return body()
    }
}
