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
        /// Where the conversation is happening — a project and branch, a room,
        /// a channel. Shown first on the row's header line.
        public let context: String
        /// What the conversation is called. Shown parenthesised after
        /// ``context``, and omitted when empty.
        public let name: String
        /// SF Symbol for the speaker, shown in the row's icon column.
        public let iconSymbol: String

        public init(sourceID: String, context: String, name: String, iconSymbol: String) {
            self.sourceID = sourceID
            self.context = context
            self.name = name
            self.iconSymbol = iconSymbol
        }

        /// The header line: `context (name)`, or just one of them when the other
        /// is missing. A live session often has no name yet — its title is
        /// written when it ends — so this has to render without one.
        public var headerLine: String {
            switch (context.isEmpty, name.isEmpty) {
            case (true, true): return ""
            case (false, true): return context
            case (true, false): return name
            case (false, false): return "\(context) (\(name))"
            }
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
        attribution: Attribution? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
        self.timestamp = timestamp
        self.attribution = attribution
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
