// Core/Chat/ChatMessage.swift
import Foundation

/// A single message in a chat transcript. `text` is mutable so streaming
/// deltas grow the in-flight assistant message in place; `isStreaming` is true
/// between `responseStarted` and `responseFinished` so the view can show a caret.
public struct ChatMessage: Identifiable, Equatable, Sendable {
    public let id: String
    public let role: Role
    public var text: String
    public var isStreaming: Bool
    public let timestamp: Date
    /// Who said it and where, for a transcript that carries more than one
    /// conversation. Nil for an ordinary one-to-one chat, where the two roles
    /// already say everything a reader needs.
    public let attribution: Attribution?

    /// Whether this message is known to have arrived where it was going.
    ///
    /// Only ever anything but ``Delivery/settled`` for a message this client
    /// wrote into a conversation it is *watching* — a transcript read off disk
    /// is a record of what happened, and a record cannot be in flight. There the
    /// round trip is long and indirect (a terminal, a shell, a hook, a file),
    /// long enough that a message shown as if it had landed is a lie for
    /// seconds at a stretch.
    public var delivery: Delivery

    /// Where a message is between "typed" and "seen coming back".
    public enum Delivery: Sendable, Equatable {
        /// It is part of the record. Everything read from a source is this.
        case settled
        /// Written, not yet seen in the source's own transcript.
        case sending
        /// It never came back, and this is why — shown under the message rather
        /// than in an alert, because what failed is *this line* and the reader
        /// needs to see which one while deciding whether to type it again.
        case failed(String)
    }

    /// The provenance of a message in a *merged* transcript — several
    /// conversations interleaved on one timeline, the way a group chat or an
    /// activity feed reads.
    ///
    /// Held on the message rather than resolved by the view because a merged
    /// transcript has no single subject to look anything up against: whatever
    /// produced the message is the only thing that knows where it came from.
    public struct Attribution: Sendable, Equatable {
        /// Opaque handle to whatever produced the message. The view hands it
        /// back on a row tap; only the host knows what to do with it.
        public let sourceID: String
        /// Where the conversation is happening, broadest first — a project then
        /// a branch, an organisation then a room. Shown as the crumbs of the
        /// row's header trail, in that order.
        ///
        /// A list rather than one string because the row draws the segments
        /// apart from each other — each in the colour that says what kind of
        /// fact it is — and a joined string cannot be taken back apart: a branch
        /// name has slashes of its own.
        public let context: [String]
        /// What the conversation is called. The last crumb of the trail, and
        /// omitted when empty — a live session often has no name yet, because
        /// its title is written when it ends.
        public let name: String
        /// SF Symbol for the speaker, shown in the row's icon column.
        public let iconSymbol: String
        /// The application the conversation is happening in — a `TERM_PROGRAM`
        /// value where the source is a terminal session, empty where there is
        /// nothing to say.
        ///
        /// A bare string rather than an image because this layer is
        /// Foundation-only, and because the string is the durable fact: what
        /// icon it resolves to depends on what is installed and running on this
        /// machine at the moment the row is drawn.
        public let appIdentity: String

        public init(
            sourceID: String,
            context: [String],
            name: String,
            iconSymbol: String,
            appIdentity: String = ""
        ) {
            self.sourceID = sourceID
            self.context = context
            self.name = name
            self.iconSymbol = iconSymbol
            self.appIdentity = appIdentity
        }

        /// The whole trail as one string, for a tooltip or a screen reader —
        /// which read a line, not a row of labels. Renders whatever segments
        /// there are, so a nameless or context-less message still says
        /// something.
        public var headerLine: String {
            (context + (name.isEmpty ? [] : [name]))
                .filter { !$0.isEmpty }
                .joined(separator: " » ")
        }
    }

    public enum Role: Sendable, Equatable {
        case user
        case assistant
        case error
        /// A centered, muted status line (e.g. "Model changed to …"). Rendered
        /// inline but never sent back to the model as conversation history.
        case notice
    }

    public init(
        id: String = UUID().uuidString,
        role: Role,
        text: String,
        isStreaming: Bool = false,
        timestamp: Date = Date(),
        attribution: Attribution? = nil,
        delivery: Delivery = .settled
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
        self.timestamp = timestamp
        self.attribution = attribution
        self.delivery = delivery
    }
}

extension ChatMessage.Role {
    /// The lowercase label the AppleScript transcript commands use for this role.
    /// One source of truth so the two scripting call sites can't drift apart.
    public var scriptingLabel: String {
        switch self {
        case .user: return "user"
        case .assistant: return "assistant"
        case .error: return "error"
        case .notice: return "notice"
        }
    }
}
