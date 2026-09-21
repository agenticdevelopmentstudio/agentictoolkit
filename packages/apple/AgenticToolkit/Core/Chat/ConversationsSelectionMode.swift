// Core/Chat/ConversationsSelectionMode.swift
import Foundation

/// How many conversations the Conversations window draws at once.
///
/// The two modes are not two filters, they are two different windows sharing a
/// frame. **Multi** is the merged feed this window was built as: any number of
/// sessions on one timeline, read side by side, and a bubble you open to see
/// its conversation in isolation. **Single** is one conversation, whole — so
/// there is nothing to isolate (the focus overlay has no job) and the composer
/// is unambiguous, because there is exactly one session a typed line could be
/// addressed to.
///
/// That is the whole reason the mode exists rather than "tick one box": with one
/// session ticked, a merged feed still cannot know that the next line you type
/// belongs to it, and a reader ticking their way down a list one session at a
/// time wants the arrow keys to move, not a tick to be cleared and another set.
///
/// Lives in `Core` rather than beside the window because the shelf, the feed,
/// the toolbar control and the host's View menu all decide things by it, and
/// three of those four are in different tiers.
public enum ConversationsSelectionMode: String, Sendable, Codable, CaseIterable {

    /// Exactly one session is shown, and the arrow keys move which one.
    case single

    /// Any number of sessions are shown, merged onto one timeline.
    case multi

    /// What the mode is called where a reader sees it named.
    public var title: String {
        switch self {
        case .single: return "Single Conversation"
        case .multi:  return "Multiple Conversations"
        }
    }

    /// The other one — what a toggle switches to.
    public var toggled: ConversationsSelectionMode {
        self == .single ? .multi : .single
    }
}
